// CosmoOS/Cosmo/ResearchService.swift
// Web research via OpenRouter/Perplexity API
// This is the ONLY network-dependent feature - everything else is local-first

import Foundation

@MainActor
final class ResearchService {
    static let shared = ResearchService()

    // OpenRouter API configuration
    private let openRouterBaseURL = "https://openrouter.ai/api/v1"
    private let perplexityModel = "perplexity/sonar"

    // API key is loaded from Keychain via APIKeys
    private var apiKey: String? {
        APIKeys.openRouter
    }

    private init() {}

    // MARK: - Perform Research
    func performResearch(
        query: String,
        searchType: ResearchSearchType = .web,
        maxResults: Int = 5
    ) async throws -> ResearchResult {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ResearchError.noAPIKey
        }

        print("🔬 Research: Calling Perplexity via OpenRouter...")
        print("   Query: \(query)")
        print("   Type: \(searchType)")

        // Build the research prompt
        let prompt = buildResearchPrompt(query: query, searchType: searchType, maxResults: maxResults)

        // Make API request
        let response = try await callOpenRouter(prompt: prompt, model: perplexityModel)

        // Parse response into structured findings
        let result = parseResearchResponse(response, query: query)

        print("✅ Research complete: \(result.findings.count) findings")

        return result
    }

    // MARK: - Build Research Prompt
    private func buildResearchPrompt(
        query: String,
        searchType: ResearchSearchType,
        maxResults: Int
    ) -> String {
        switch searchType {
        case .web:
            return """
            Search the web for current, accurate information about: \(query)

            Please provide:
            1. A concise summary (2-3 sentences)
            2. Up to \(maxResults) key findings with sources
            3. Any relevant statistics or data points

            Format your response as JSON with this structure:
            {
              "summary": "Brief overview...",
              "findings": [
                {
                  "title": "Finding title",
                  "snippet": "Key information...",
                  "source": "Source name",
                  "url": "https://...",
                  "confidence": "high/medium/low"
                }
              ]
            }
            """

        case .reddit:
            return """
            Search Reddit for discussions and opinions about: \(query)

            Focus on:
            - Real user experiences and opinions
            - Common pain points and problems
            - Popular solutions and recommendations

            Please provide up to \(maxResults) relevant Reddit discussions.

            Format as JSON:
            {
              "summary": "What Reddit users are saying...",
              "findings": [
                {
                  "title": "Discussion topic",
                  "snippet": "Key quote or summary...",
                  "source": "r/subreddit",
                  "url": "https://reddit.com/...",
                  "upvotes": 0,
                  "sentiment": "positive/negative/neutral"
                }
              ]
            }
            """

        case .academic:
            return """
            Search for academic and research papers about: \(query)

            Focus on:
            - Recent peer-reviewed research
            - Key studies and findings
            - Expert consensus

            Provide up to \(maxResults) relevant academic sources.

            Format as JSON:
            {
              "summary": "Research overview...",
              "findings": [
                {
                  "title": "Paper title",
                  "snippet": "Key finding...",
                  "source": "Journal/Institution",
                  "authors": "Author names",
                  "year": 2024,
                  "citations": 0
                }
              ]
            }
            """

        case .news:
            return """
            Search for recent news about: \(query)

            Focus on:
            - Recent developments (last 30 days preferred)
            - Multiple perspectives
            - Verified sources

            Provide up to \(maxResults) news articles.

            Format as JSON:
            {
              "summary": "Recent news overview...",
              "findings": [
                {
                  "title": "Article headline",
                  "snippet": "Key information...",
                  "source": "Publication name",
                  "url": "https://...",
                  "date": "2024-12-11"
                }
              ]
            }
            """
        }
    }

    // MARK: - Content Analysis (Claude Sonnet 4.5)

    /// Analyze content with Claude Sonnet 4.5 via OpenRouter — used for deep swipe analysis
    func analyzeContent(prompt: String) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ResearchError.noAPIKey
        }

        let claudeModel = "anthropic/claude-sonnet-4.5"
        return try await callOpenRouter(
            prompt: prompt,
            model: claudeModel,
            maxTokens: 4000,
            temperature: 0.2
        )
    }

    // MARK: - Call OpenRouter API
    private func callOpenRouter(prompt: String, model: String, maxTokens: Int = 2000, temperature: Double = 0.3) async throws -> String {
        guard let apiKey = apiKey else {
            throw ResearchError.noAPIKey
        }

        let url = URL(string: "\(openRouterBaseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CosmoOS/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("CosmoOS", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ResearchError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ OpenRouter error \(httpResponse.statusCode): \(errorText)")
            throw ResearchError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }

        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String ?? ""

        return content
    }

    // MARK: - Parse Research Response
    private func parseResearchResponse(_ response: String, query: String) -> ResearchResult {
        // Try to parse as JSON
        if let jsonData = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

            let summary = json["summary"] as? String ?? response
            let findingsArray = json["findings"] as? [[String: Any]] ?? []

            let findings = findingsArray.compactMap { finding -> ResearchFinding? in
                guard let title = finding["title"] as? String else { return nil }

                return ResearchFinding(
                    title: title,
                    snippet: finding["snippet"] as? String,
                    source: finding["source"] as? String ?? "Web",
                    url: finding["url"] as? String,
                    confidence: finding["confidence"] as? String ?? "medium"
                )
            }

            return ResearchResult(
                query: query,
                summary: summary,
                findings: findings
            )
        }

        // Fallback: treat entire response as summary
        return ResearchResult(
            query: query,
            summary: response,
            findings: [
                ResearchFinding(
                    title: "Research Result",
                    snippet: String(response.prefix(500)),
                    source: "Perplexity AI",
                    url: nil,
                    confidence: "medium"
                )
            ]
        )
    }
}

// MARK: - Research Types
enum ResearchSearchType: String, Codable {
    case web = "WEB"
    case reddit = "REDDIT"
    case academic = "ACADEMIC"
    case news = "NEWS"
}

struct ResearchResult: Codable {
    let query: String
    let summary: String
    let findings: [ResearchFinding]
}

struct ResearchFinding: Codable, Identifiable, Equatable {
    let id = UUID()
    let title: String
    let snippet: String?
    let source: String
    let url: String?
    let confidence: String

    enum CodingKeys: String, CodingKey {
        case title, snippet, source, url, confidence
    }

    static func == (lhs: ResearchFinding, rhs: ResearchFinding) -> Bool {
        // Intentionally ignore `id` (it's runtime-only and not persisted)
        lhs.title == rhs.title &&
            lhs.snippet == rhs.snippet &&
            lhs.source == rhs.source &&
            lhs.url == rhs.url &&
            lhs.confidence == rhs.confidence
    }
}

// MARK: - Research Errors
enum ResearchError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parsingError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenRouter API key configured. Please add OPENROUTER_API_KEY to your environment."
        case .invalidResponse:
            return "Invalid response from research API"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .parsingError:
            return "Failed to parse research results"
        }
    }
}
