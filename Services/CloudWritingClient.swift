// CosmoOS/Services/CloudWritingClient.swift
// Thin client for the canonical cloud writing engine.
// Replaces local UnifiedWritingEngine calls — both TG and in-app
// now use the same cloud engine for guaranteed quality parity.

import Foundation

@MainActor
class CloudWritingClient {
    static let shared = CloudWritingClient()

    private let baseURL: String
    private let session: URLSession

    private init() {
        self.baseURL = "https://cosmonative-production.up.railway.app"
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 min for Opus on large contexts
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    // MARK: - Result Types

    struct OutlineResult: Codable {
        let success: Bool
        let contentUUID: String?
        let message: String?
        let outlineSections: [String]?
        let hookVariants: [String]?
        let sectionCount: Int?
        let hookCount: Int?
        let swipesLoaded: [String]?
        let swipeCount: Int?
        let error: String?
    }

    struct DraftResult: Codable {
        let success: Bool
        let contentUUID: String?
        let message: String?
        let formattedDraft: String?
        let format: String?
        let wordCount: Int?
        let title: String?
        let engineNotes: String?
        let swipesLoaded: [String]?
        let swipeCount: Int?
        let error: String?
    }

    // MARK: - API Methods

    func generateOutline(
        contentUUID: String,
        blueprintTitles: [String]? = nil,
        blueprintSwipeUUIDs: [String]? = nil,
        notes: String? = nil,
        clientName: String? = nil,
        contentFormat: String? = nil,
        contextAtomUUIDs: [String]? = nil
    ) async throws -> OutlineResult {
        var body: [String: Any] = ["contentUUID": contentUUID]
        if let blueprintTitles { body["blueprintTitles"] = blueprintTitles }
        if let blueprintSwipeUUIDs { body["blueprintSwipeUUIDs"] = blueprintSwipeUUIDs }
        if let notes { body["notes"] = notes }
        if let clientName { body["clientName"] = clientName }
        if let contentFormat { body["contentFormat"] = contentFormat }
        if let contextAtomUUIDs { body["contextAtomUUIDs"] = contextAtomUUIDs }

        return try await post(path: "/api/writing/outline", body: body)
    }

    func generateDraft(
        contentUUID: String,
        userDirection: String? = nil,
        clientName: String? = nil,
        contentFormat: String? = nil
    ) async throws -> DraftResult {
        var body: [String: Any] = ["contentUUID": contentUUID]
        if let userDirection { body["userDirection"] = userDirection }
        if let clientName { body["clientName"] = clientName }
        if let contentFormat { body["contentFormat"] = contentFormat }

        return try await post(path: "/api/writing/draft", body: body)
    }

    func reviseDraft(
        contentUUID: String,
        feedback: String,
        currentDraft: String? = nil,
        clientName: String? = nil
    ) async throws -> DraftResult {
        var body: [String: Any] = ["contentUUID": contentUUID, "feedback": feedback]
        if let currentDraft { body["currentDraft"] = currentDraft }
        if let clientName { body["clientName"] = clientName }

        return try await post(path: "/api/writing/revise", body: body)
    }

    func readDraft(contentUUID: String) async throws -> DraftResult {
        return try await post(path: "/api/writing/read", body: ["contentUUID": contentUUID])
    }

    /// Single agentic session — outline-required mode.
    /// Runs all phases (plan + write + self-edit) in one Opus API call with adaptive thinking.
    /// Used when content atom has a codex-tagged outline.
    /// Passes local metadata to avoid Supabase sync race conditions.
    func runSession(
        contentUUID: String,
        userDirection: String? = nil,
        localMetadata: [String: Any]? = nil
    ) async throws -> DraftResult {
        var body: [String: Any] = ["contentUUID": contentUUID]
        if let userDirection { body["userDirection"] = userDirection }
        if let localMetadata { body["localMetadata"] = localMetadata }

        return try await post(path: "/api/writing/session", body: body)
    }

    // MARK: - HTTP

    private func post<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw CloudWritingError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Shared secret for cloud writing API authentication
        let apiKey = APIKeys.supabaseServiceRoleKey ?? "cosmo-native-writing-2026"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("☁️ [CloudWriting] \(path) → \(body["contentUUID"] as? String ?? "?")")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudWritingError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw CloudWritingError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudWritingError.serverError(statusCode: httpResponse.statusCode, message: errorText)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Errors

enum CloudWritingError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(statusCode: Int, message: String)
    case offline

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid cloud writing URL"
        case .invalidResponse: return "Invalid response from cloud writing engine"
        case .unauthorized: return "Authentication failed — check API key"
        case .serverError(let code, let msg): return "Cloud writing error \(code): \(msg)"
        case .offline: return "No internet connection — cloud writing unavailable"
        }
    }
}
