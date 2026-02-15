// CosmoOS/AI/PolishEngine.swift
// AI-powered writing suggestion engine
// Uses OpenRouter (Gemini) to generate actionable writing improvements
// based on WritingAnalyzer results
// February 2026

import Foundation

// AISuggestion is defined in ContentFocusModeState.swift

// MARK: - Polish Engine

/// AI-powered suggestion engine that generates writing improvements
/// based on WritingAnalyzer results. Uses OpenRouter API via Gemini.
final class PolishEngine {
    static let shared = PolishEngine()

    private let baseURL = "https://openrouter.ai/api/v1"
    private let model = "google/gemini-3-flash-preview"

    static let defaultSystemPrompt = """
        You are a precise writing editor. Your job is to suggest specific, actionable improvements \
        for clarity, conciseness, and readability. Focus on:
        1. Simplifying complex sentences (break long sentences into shorter ones)
        2. Converting passive voice to active voice
        3. Removing unnecessary adverbs and filler words
        4. Improving word choice for precision
        Keep the author's voice and intent. Only suggest changes that meaningfully improve the text.
        """

    private init() {}

    // MARK: - Generate Suggestions

    /// Generate AI writing suggestions based on text and analysis results
    func generateSuggestions(
        text: String,
        analysis: WritingAnalysis,
        systemPrompt: String?,
        maxSuggestions: Int = 10,
        profileContext: String? = nil
    ) async throws -> [AISuggestion] {
        guard let apiKey = APIKeys.openRouter, !apiKey.isEmpty else {
            print("PolishEngine: No OpenRouter API key configured, returning empty suggestions")
            return []
        }

        let prompt = buildPrompt(text: text, analysis: analysis, maxSuggestions: maxSuggestions, profileContext: profileContext)
        let system = systemPrompt ?? Self.defaultSystemPrompt

        let responseText = try await callAPI(prompt: prompt, systemPrompt: system, apiKey: apiKey)
        return parseSuggestions(from: responseText)
    }

    // MARK: - Prompt Building

    private func buildPrompt(text: String, analysis: WritingAnalysis, maxSuggestions: Int, profileContext: String? = nil) -> String {
        var prompt = "Analyze the following text and suggest up to \(maxSuggestions) specific improvements.\n\n"

        // Inject client profile context if available
        if let context = profileContext, !context.isEmpty {
            prompt += context + "\n\n"
            prompt += "Ensure suggestions maintain the brand voice and style described above.\n\n"
        }

        // Add analysis context to focus the AI
        prompt += "ANALYSIS SUMMARY:\n"
        prompt += "- Flesch-Kincaid: \(String(format: "%.1f", analysis.fleschKincaidScore)) (grade level: \(String(format: "%.1f", analysis.gradeLevel)))\n"
        prompt += "- Avg sentence length: \(String(format: "%.1f", analysis.avgSentenceLength)) words\n"
        prompt += "- Passive voice: \(String(format: "%.1f", analysis.passiveVoicePercent))%\n"
        prompt += "- Adverb density: \(String(format: "%.1f", analysis.adverbDensity))%\n"

        if !analysis.veryComplexSentenceRanges.isEmpty {
            prompt += "- \(analysis.veryComplexSentenceRanges.count) very complex sentences (>25 words)\n"
        }
        if !analysis.complexSentenceRanges.isEmpty {
            prompt += "- \(analysis.complexSentenceRanges.count) complex sentences (15-25 words)\n"
        }

        // Include problem areas
        let nsText = text as NSString
        if !analysis.passiveVoiceRanges.isEmpty {
            prompt += "\nPASSIVE VOICE INSTANCES:\n"
            for (i, range) in analysis.passiveVoiceRanges.prefix(5).enumerated() {
                if range.location + range.length <= nsText.length {
                    prompt += "\(i+1). \"\(nsText.substring(with: range))\"\n"
                }
            }
        }

        prompt += "\nTEXT TO IMPROVE:\n\"\"\"\n\(text)\n\"\"\"\n\n"

        prompt += """
            RESPOND IN THIS EXACT FORMAT (one suggestion per block, no other text):

            ---SUGGESTION---
            ORIGINAL: exact text from the original
            SUGGESTED: your improved version
            REASON: brief explanation (1 sentence)
            CATEGORY: one of [clarity, activeVoice, conciseness, structure, wordChoice]
            ---END---
            """

        return prompt
    }

    // MARK: - API Call

    private func callAPI(prompt: String, systemPrompt: String, apiKey: String) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CosmoOS/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("CosmoOS Writing Polish", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.4,
            "max_tokens": 3000,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PolishError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PolishError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PolishError.parsingError
        }

        return content
    }

    // MARK: - Response Parsing

    private func parseSuggestions(from response: String) -> [AISuggestion] {
        var suggestions: [AISuggestion] = []

        // Split by suggestion blocks
        let blocks = response.components(separatedBy: "---SUGGESTION---")

        for block in blocks {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Extract fields
            guard let original = extractField("ORIGINAL:", from: trimmed),
                  let suggested = extractField("SUGGESTED:", from: trimmed),
                  let reason = extractField("REASON:", from: trimmed) else {
                continue
            }

            suggestions.append(AISuggestion(
                originalText: original,
                suggestedText: suggested,
                reason: reason
            ))
        }

        return suggestions
    }

    /// Extract a field value from a structured text block
    private func extractField(_ prefix: String, from text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix(prefix) {
                var value = String(trimmedLine.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Handle multi-line values (until next field or end marker)
                let nextPrefixes = ["ORIGINAL:", "SUGGESTED:", "REASON:", "CATEGORY:", "---END---"]
                for nextLine in lines[(i+1)...] {
                    let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                    if nextPrefixes.contains(where: { nextTrimmed.hasPrefix($0) }) {
                        break
                    }
                    if !nextTrimmed.isEmpty {
                        value += " " + nextTrimmed
                    }
                }

                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}

// MARK: - Polish Errors

enum PolishError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parsingError
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from writing polish API"
        case .apiError(let code, let message):
            return "Polish API error (\(code)): \(message)"
        case .parsingError:
            return "Failed to parse polish suggestions"
        case .noAPIKey:
            return "No API key configured for writing polish"
        }
    }
}
