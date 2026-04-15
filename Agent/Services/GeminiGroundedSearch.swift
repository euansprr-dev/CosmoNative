// CosmoOS/Agent/Services/GeminiGroundedSearch.swift
// Gemini-powered web search for the focus-mode margin Cosmo agent.
//
// The margin Cosmo panel is pinned to google/gemini-3-flash for EVERY model-facing
// call — including the web_search tool. This service exists so `FocusCosmoAgent`
// can intercept web_search and route it to Gemini instead of the default Perplexity
// path used by `AgentToolExecutor.webSearch(...)` (which the global ⌘J window still
// consumes).
//
// V1 strategy: call Gemini 3 Flash with a research-oriented prompt and let it
// ground against whatever knowledge / search backends OpenRouter surfaces for the
// Google passthrough. If Gemini returns text with URLs, we extract them. If it
// returns only prose, we still return the prose as the `summary` field so the
// calling agent has useful context.

import Foundation

@MainActor
final class GeminiGroundedSearch {
    static let shared = GeminiGroundedSearch()
    private init() {}

    private lazy var provider: LLMProvider = {
        LLMProviderFactory.create(
            provider: .openRouter,
            apiKey: APIKeys.openRouter,
            baseURL: nil
        )
    }()

    /// Run a web research query via Gemini 3 Flash and return a JSON string shaped
    /// like `{ "success": true, "query": "...", "summary": "...", "findings": [...] }`
    /// so the calling agent sees the same structure `AgentToolExecutor.webSearch`
    /// returns for the Perplexity path.
    func search(query: String, model: String, maxResults: Int = 5) async -> String {
        let systemPrompt = """
        You are a research assistant. The user will give you a query. Respond with:
        1. A concise two-to-four-sentence summary of the most relevant facts.
        2. Up to \(maxResults) key findings, each on its own line, each in the format:
           `• <short title> — <one-sentence fact> <http://url if you have one>`

        Be factual, cite URLs when you have them, and keep the entire response under
        250 words. If you do not know the answer or can't ground it, say so explicitly.
        """

        let messages: [AgentMessage] = [
            .system(systemPrompt),
            .user("Research: \(query)")
        ]

        do {
            let response = try await provider.complete(
                messages: messages,
                tools: nil,
                model: model
            )
            let rawText = response.content ?? ""
            return packageResponse(query: query, text: rawText)
        } catch {
            return packageError(query: query, error: error.localizedDescription)
        }
    }

    // MARK: - Response packaging

    private func packageResponse(query: String, text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let (summary, findings) = parse(text: trimmed)
        let payload: [String: Any] = [
            "success": true,
            "query": query,
            "summary": summary,
            "findings": findings,
            "count": findings.count,
            "source": "gemini-grounded"
        ]
        return jsonEncode(payload)
    }

    private func packageError(query: String, error: String) -> String {
        let payload: [String: Any] = [
            "success": false,
            "query": query,
            "error": "Gemini web search failed: \(error)",
            "source": "gemini-grounded"
        ]
        return jsonEncode(payload)
    }

    /// Parse Gemini's free-form response into a summary paragraph + finding rows.
    /// Finding rows are lines starting with `•` or `-`; everything else becomes part
    /// of the summary paragraph. URLs inside a finding line are extracted.
    private func parse(text: String) -> (summary: String, findings: [[String: Any]]) {
        var summaryLines: [String] = []
        var findings: [[String: Any]] = []

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("•") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") {
                let body = trimmed
                    .trimmingCharacters(in: CharacterSet(charactersIn: "•-* "))
                let url = extractURL(from: body)
                let title: String
                let snippet: String
                if let dashRange = body.range(of: " — ") ?? body.range(of: " - ") {
                    title = String(body[..<dashRange.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    snippet = String(body[dashRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                } else {
                    title = body
                    snippet = ""
                }
                findings.append([
                    "title": title,
                    "snippet": snippet,
                    "url": url ?? ""
                ])
            } else {
                summaryLines.append(trimmed)
            }
        }

        return (summaryLines.joined(separator: " "), findings)
    }

    private func extractURL(from text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let match = detector.firstMatch(in: text, options: [], range: range)
        return match?.url?.absoluteString
    }

    private func jsonEncode(_ dict: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{\"success\": false, \"error\": \"encoding failed\"}"
    }
}
