// CosmoOS/AI/PerplexityService.swift
// Perplexity API client for Research Agent queries
// Provides web search + AI synthesis for research tasks
// December 2025 - Research Focus Mode integration

import Foundation

// MARK: - Perplexity Service

/// Service for interacting with the Perplexity API.
/// Used by Research Agent to search the web and synthesize findings.
actor PerplexityService {
    // MARK: - Singleton

    static let shared = PerplexityService()

    // MARK: - Configuration

    private let baseURL = "https://api.perplexity.ai/chat/completions"
    private let defaultModel = "sonar-medium-online"

    // MARK: - API Key

    /// Get API key from settings/keychain
    private var apiKey: String? {
        // First try environment variable (for development)
        if let envKey = ProcessInfo.processInfo.environment["PERPLEXITY_API_KEY"] {
            return envKey
        }

        // Then try UserDefaults (user-configured)
        if let storedKey = UserDefaults.standard.string(forKey: "perplexity_api_key"),
           !storedKey.isEmpty {
            return storedKey
        }

        // Finally try Keychain
        return KeychainHelper.shared.get(key: "perplexity_api_key")
    }

    // MARK: - Public Methods

    /// Perform a research query using Perplexity's web search + synthesis
    /// - Parameter query: The research question to answer
    /// - Returns: Research result with summary, citations, and related questions
    func research(query: String) async throws -> PerplexityResult {
        guard let key = apiKey, !key.isEmpty else {
            throw PerplexityError.missingAPIKey
        }

        let request = PerplexityRequest(
            model: defaultModel,
            messages: [
                PerplexityMessage(
                    role: "system",
                    content: """
                    You are a research assistant. Provide comprehensive, well-sourced answers.
                    Focus on factual information and cite your sources.
                    Be concise but thorough.
                    """
                ),
                PerplexityMessage(role: "user", content: query)
            ],
            returnCitations: true,
            returnRelatedQuestions: true
        )

        let response = try await performRequest(request, apiKey: key)
        return parseResponse(response, query: query)
    }

    /// Perform a focused research query on a specific topic
    /// - Parameters:
    ///   - query: The research question
    ///   - context: Additional context to focus the search
    /// - Returns: Research result
    func researchWithContext(query: String, context: String) async throws -> PerplexityResult {
        guard let key = apiKey, !key.isEmpty else {
            throw PerplexityError.missingAPIKey
        }

        let request = PerplexityRequest(
            model: defaultModel,
            messages: [
                PerplexityMessage(
                    role: "system",
                    content: """
                    You are a research assistant helping with a specific topic.
                    Context: \(context)

                    Provide relevant, well-sourced information that connects to this context.
                    Focus on practical insights and actionable information.
                    """
                ),
                PerplexityMessage(role: "user", content: query)
            ],
            returnCitations: true,
            returnRelatedQuestions: true
        )

        let response = try await performRequest(request, apiKey: key)
        return parseResponse(response, query: query)
    }

    // MARK: - Private Methods

    private func performRequest(_ request: PerplexityRequest, apiKey: String) async throws -> PerplexityAPIResponse {
        guard let url = URL(string: baseURL) else {
            throw PerplexityError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PerplexityError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(PerplexityAPIResponse.self, from: data)

        case 401:
            throw PerplexityError.invalidAPIKey

        case 429:
            throw PerplexityError.rateLimited

        case 500...599:
            throw PerplexityError.serverError(httpResponse.statusCode)

        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PerplexityError.apiError(httpResponse.statusCode, errorMessage)
        }
    }

    private func parseResponse(_ response: PerplexityAPIResponse, query: String) -> PerplexityResult {
        guard let choice = response.choices.first else {
            return PerplexityResult(
                query: query,
                summary: "No response received.",
                citations: [],
                relatedQuestions: [],
                model: response.model,
                tokensUsed: response.usage?.totalTokens ?? 0
            )
        }

        let summary = choice.message.content

        // Parse citations from response
        var citations: [PerplexityResult.Citation] = []
        if let responseCitations = response.citations {
            citations = responseCitations.enumerated().map { index, urlString in
                PerplexityResult.Citation(
                    index: index + 1,
                    url: urlString,
                    title: extractDomain(from: urlString),
                    snippet: nil
                )
            }
        }

        // Related questions (if supported by response)
        let relatedQuestions = response.relatedQuestions ?? []

        return PerplexityResult(
            query: query,
            summary: summary,
            citations: citations,
            relatedQuestions: relatedQuestions,
            model: response.model,
            tokensUsed: response.usage?.totalTokens ?? 0
        )
    }

    private func extractDomain(from url: String) -> String {
        guard let urlObj = URL(string: url),
              let host = urlObj.host else {
            return url
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

// MARK: - Request Models

struct PerplexityRequest: Encodable {
    let model: String
    let messages: [PerplexityMessage]
    let returnCitations: Bool
    let returnRelatedQuestions: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case returnCitations = "return_citations"
        case returnRelatedQuestions = "return_related_questions"
    }
}

struct PerplexityMessage: Encodable {
    let role: String
    let content: String
}

// MARK: - Response Models

struct PerplexityAPIResponse: Decodable {
    let id: String
    let model: String
    let choices: [PerplexityChoice]
    let citations: [String]?
    let relatedQuestions: [String]?
    let usage: PerplexityUsage?

    enum CodingKeys: String, CodingKey {
        case id
        case model
        case choices
        case citations
        case relatedQuestions = "related_questions"
        case usage
    }
}

struct PerplexityChoice: Decodable {
    let index: Int
    let message: PerplexityResponseMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

struct PerplexityResponseMessage: Decodable {
    let role: String
    let content: String
}

struct PerplexityUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Result Model

/// Result from a Perplexity research query
struct PerplexityResult {
    let query: String
    let summary: String
    let citations: [Citation]
    let relatedQuestions: [String]
    let model: String
    let tokensUsed: Int

    struct Citation {
        let index: Int
        let url: String
        let title: String
        let snippet: String?
    }
}

// MARK: - Errors

enum PerplexityError: Error, LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case invalidURL
    case invalidResponse
    case rateLimited
    case serverError(Int)
    case apiError(Int, String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Perplexity API key not configured. Add it in Settings."
        case .invalidAPIKey:
            return "Invalid Perplexity API key. Please check your settings."
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Invalid response from Perplexity API."
        case .rateLimited:
            return "Rate limited. Please wait before trying again."
        case .serverError(let code):
            return "Perplexity server error (\(code)). Please try again later."
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Keychain Helper

/// Simple keychain helper for API key storage
class KeychainHelper {
    static let shared = KeychainHelper()

    private let service = "com.cosmo.perplexity"

    func set(key: String, value: String) {
        let data = Data(value.utf8)

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
