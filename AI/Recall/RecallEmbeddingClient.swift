// CosmoOS/AI/Recall/RecallEmbeddingClient.swift
// Embedding source for the Recall semantic foundation. Cloud-backed: the app
// already depends on cloud LLMs for writing/routing, and the on-device MLX
// path shipped as a dormant stub (no embeddings ever existed). Speaks the
// OpenAI embeddings wire format, which OpenAI, Voyage, Mistral, and Together
// all serve — the provider is just a base URL + model + key.
// July 2026

import Foundation

// MARK: - Client Protocol

protocol RecallEmbeddingClient: Sendable {
    /// Identifies the model so index rows can be invalidated on model swaps.
    var modelID: String { get }
    /// True when the client is configured well enough to attempt a request.
    var isConfigured: Bool { get }
    /// Embed a batch of texts. Returns one vector per input, same order.
    func embed(_ texts: [String]) async throws -> [[Float]]
}

enum RecallEmbeddingError: LocalizedError {
    case notConfigured
    case badResponse(status: Int, body: String)
    case countMismatch(expected: Int, got: Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No embeddings API key configured (Settings → Connections → Service Keys)"
        case .badResponse(let status, let body):
            return "Embeddings API error \(status): \(body.prefix(200))"
        case .countMismatch(let expected, let got):
            return "Embeddings API returned \(got) vectors for \(expected) inputs"
        }
    }
}

/// The embeddings integration's health, recorded at the one choke point every
/// cloud embedding call flows through. Memory recall, the Recall index, and
/// exemplar retrieval all die silently when embeddings fail — this is how the
/// UI tells the user exactly what is wrong (missing key, bad key, API error)
/// instead of degrading in silence.
final class EmbeddingHealth: @unchecked Sendable {
    static let shared = EmbeddingHealth()

    private let lock = NSLock()
    private var lastErrorStorage: String?

    /// The most recent failure, cleared by the next success. Nil = healthy
    /// (or no attempt yet this session).
    var lastError: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastErrorStorage
    }

    func recordSuccess() {
        lock.lock()
        lastErrorStorage = nil
        lock.unlock()
    }

    func recordFailure(_ message: String) {
        lock.lock()
        lastErrorStorage = message
        lock.unlock()
    }

    /// One-line diagnosis for UI surfaces, nil when healthy. Missing key wins
    /// (it's the actionable case); otherwise the most recent runtime failure.
    var userFacingIssue: String? {
        if !APIKeys.hasEmbeddings {
            return "No embeddings API key — add one in Settings → Connections → Service Keys."
        }
        return lastError.map { "Embeddings are failing: \($0)" }
    }
}

// MARK: - Cloud Client (OpenAI wire format)

struct CloudEmbeddingClient: RecallEmbeddingClient {
    /// Defaults; both overridable so a provider swap is a settings change.
    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "text-embedding-3-small"

    static let baseURLDefaultsKey = "recall.embeddings.baseURL"
    static let modelDefaultsKey = "recall.embeddings.model"

    /// Max texts per request — well under every provider's batch limit.
    static let maxBatchSize = 128

    var baseURL: String {
        UserDefaults.standard.string(forKey: Self.baseURLDefaultsKey) ?? Self.defaultBaseURL
    }

    var modelID: String {
        UserDefaults.standard.string(forKey: Self.modelDefaultsKey) ?? Self.defaultModel
    }

    var isConfigured: Bool {
        APIKeys.hasEmbeddings
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        guard let key = APIKeys.embeddings, !key.isEmpty else {
            EmbeddingHealth.shared.recordFailure(RecallEmbeddingError.notConfigured.localizedDescription)
            throw RecallEmbeddingError.notConfigured
        }
        guard !texts.isEmpty else { return [] }

        var vectors: [[Float]] = []
        vectors.reserveCapacity(texts.count)

        var start = 0
        while start < texts.count {
            let slice = Array(texts[start..<min(start + Self.maxBatchSize, texts.count)])
            start += Self.maxBatchSize
            do {
                vectors.append(contentsOf: try await embedBatch(slice, key: key))
            } catch {
                EmbeddingHealth.shared.recordFailure(error.localizedDescription)
                throw error
            }
        }
        EmbeddingHealth.shared.recordSuccess()
        return vectors
    }

    private func embedBatch(_ texts: [String], key: String) async throws -> [[Float]] {
        var request = URLRequest(url: URL(string: "\(baseURL)/embeddings")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        struct RequestBody: Encodable {
            let model: String
            let input: [String]
        }
        request.httpBody = try JSONEncoder().encode(RequestBody(model: modelID, input: texts))

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw RecallEmbeddingError.badResponse(
                status: status, body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        struct ResponseBody: Decodable {
            struct Item: Decodable {
                let index: Int
                let embedding: [Float]
            }
            let data: [Item]
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard decoded.data.count == texts.count else {
            throw RecallEmbeddingError.countMismatch(expected: texts.count, got: decoded.data.count)
        }
        return decoded.data
            .sorted { $0.index < $1.index }
            .map { RecallVectorMath.normalized($0.embedding) }
    }
}

// MARK: - Shared Text Embedding Helper

/// One-line access for callers that need raw vectors (centroid math, context
/// scoring). Vectors come back L2-normalized — cosine is a plain dot product.
enum RecallEmbedding {
    static func embedText(_ text: String) async throws -> [Float] {
        guard let vector = try await CloudEmbeddingClient().embed([String(text.prefix(2_000))]).first else {
            throw RecallEmbeddingError.notConfigured
        }
        return vector
    }
}

// MARK: - Deterministic Fake (tests, offline development)

/// Hash-bucketed bag-of-words embedding: texts sharing vocabulary land near
/// each other, so the full pipeline (chunking → storage → search math →
/// ranking) is testable without a network.
struct FakeEmbeddingClient: RecallEmbeddingClient {
    let modelID = "fake-bow-256"
    let isConfigured = true
    static let dimension = 256

    func embed(_ texts: [String]) async throws -> [[Float]] {
        texts.map { Self.vector(for: $0) }
    }

    static func vector(for text: String) -> [Float] {
        var vector = [Float](repeating: 0, count: dimension)
        let tokens = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        for token in tokens {
            var hash: UInt64 = 5381
            for byte in token.utf8 {
                hash = ((hash << 5) &+ hash) &+ UInt64(byte)
            }
            vector[Int(hash % UInt64(dimension))] += 1
        }
        return RecallVectorMath.normalized(vector)
    }
}
