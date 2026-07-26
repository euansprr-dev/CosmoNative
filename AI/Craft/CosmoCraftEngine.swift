// CosmoOS/AI/Craft/CosmoCraftEngine.swift
// The craft engine's entire LLM surface: ONE structured Anthropic call per task.
// No agentic loop, no tool relay, no cloud server. Context is assembled
// deterministically by the runner; this file owns the wire format, prompt-cache
// blocks, structured-output schemas, and honest cost accounting at CURRENT
// pricing (the old engine's logger still priced legacy Opus at 3x).
// June 2026

import Foundation

// MARK: - Wire types

struct CraftSystemBlock: Sendable {
    var text: String
    /// "1h" for the stable blocks (study method, client pack); nil = uncached.
    var cacheTTL: String?
}

struct CraftUsage: Sendable {
    var inputTokens: Int
    var cacheWriteTokens: Int
    var cacheReadTokens: Int
    var outputTokens: Int

    /// Claude Opus 4.8 pricing, June 2026: $5/M in, $25/M out, cache read
    /// ~0.1x, 1h cache write 2x. Update alongside `model` below.
    var costUSD: Double {
        (Double(inputTokens) * 5.0
            + Double(cacheWriteTokens) * 10.0
            + Double(cacheReadTokens) * 0.5
            + Double(outputTokens) * 25.0) / 1_000_000
    }

    var totalPromptTokens: Int { inputTokens + cacheWriteTokens + cacheReadTokens }

    var cacheHitPercent: Int {
        guard totalPromptTokens > 0 else { return 0 }
        return Int((Double(cacheReadTokens) / Double(totalPromptTokens) * 100).rounded())
    }

    /// The receipt line rendered under every craft answer.
    var receiptLine: String {
        let inK = String(format: "%.1fK", Double(totalPromptTokens) / 1000)
        let outK = String(format: "%.1fK", Double(outputTokens) / 1000)
        return String(format: "≈$%.2f · %@ in (%d%% cached) · %@ out", costUSD, inK, cacheHitPercent, outK)
    }
}

struct CraftCompletion: Sendable {
    var text: String
    var usage: CraftUsage
}

enum CraftEngineError: LocalizedError {
    case noAPIKey
    case apiError(String)
    case emptyResponse
    case truncated

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Anthropic API key configured — set Settings → API Keys → Anthropic Agent LLM Key."
        case .apiError(let detail):
            return "Craft engine call failed: \(detail)"
        case .emptyResponse:
            return "The model returned no usable text."
        case .truncated:
            return "The model hit its output ceiling before finishing — the result was cut off."
        }
    }
}

// MARK: - Engine

enum CosmoCraftEngine {
    typealias RequestPerformer = (URLRequest) async throws -> (Data, URLResponse)

    static let model = "claude-opus-4-8"
    static let effort = "xhigh"
    static let defaultMaxTokens = 65_536

    /// One Messages API call. System blocks carry their own cache_control so
    /// the study method + client pack prefix is written once an hour and read
    /// for ~0.1x on every review, riff, and follow-up after that.
    static func complete(
        systemBlocks: [CraftSystemBlock],
        messages: [[String: Any]],
        jsonSchema: [String: Any]?,
        maxTokens: Int = defaultMaxTokens
    ) async throws -> CraftCompletion {
        guard let apiKey = APIKeys.agentLLM, !apiKey.isEmpty else {
            throw CraftEngineError.noAPIKey
        }

        return try await complete(
            systemBlocks: systemBlocks,
            messages: messages,
            jsonSchema: jsonSchema,
            maxTokens: maxTokens,
            apiKey: apiKey,
            requestPerformer: { request in
                try await URLSession.shared.data(for: request)
            }
        )
    }

    static func complete(
        systemBlocks: [CraftSystemBlock],
        messages: [[String: Any]],
        jsonSchema: [String: Any]?,
        maxTokens: Int = defaultMaxTokens,
        apiKey: String,
        maxAttempts: Int = 3,
        retryBaseBackoff: Double = 2.0,
        requestPerformer: RequestPerformer
    ) async throws -> CraftCompletion {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let system: [[String: Any]] = systemBlocks.map { block in
            var entry: [String: Any] = ["type": "text", "text": block.text]
            if let ttl = block.cacheTTL {
                entry["cache_control"] = ["type": "ephemeral", "ttl": ttl]
            }
            return entry
        }

        let body = requestBody(
            system: system,
            messages: messages,
            jsonSchema: jsonSchema,
            maxTokens: maxTokens
        )

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let httpResponse: HTTPURLResponse
        do {
            (data, httpResponse) = try await withNetworkRetry(
                maxAttempts: maxAttempts,
                baseBackoff: retryBaseBackoff,
                label: "CraftEngine",
                operation: {
                    try await requestPerformer(request)
                }
            )
        } catch let error as NetworkRetryError {
            throw CraftEngineError.apiError(error.localizedDescription)
        }

        guard httpResponse.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "unknown error"
            throw CraftEngineError.apiError("HTTP \(httpResponse.statusCode): \(detail.prefix(600))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw CraftEngineError.apiError("unparseable response body")
        }

        // A ceiling hit truncates the payload mid-structure; failing here names
        // the real cause instead of surfacing a confusing downstream parse error.
        if json["stop_reason"] as? String == "max_tokens" {
            throw CraftEngineError.truncated
        }
        if json["stop_reason"] as? String == "refusal" {
            let category = (json["stop_details"] as? [String: Any])?["category"] as? String
            throw CraftEngineError.apiError("the model declined this request\(category.map { " (\($0))" } ?? "")")
        }

        // Adaptive thinking can prepend thinking blocks, and the model
        // occasionally emits a short false-start block before the real answer —
        // taking `.first` silently picked the false start. The deliverable is the
        // longest text block; `candidatePayloads` handles JSON inside it.
        let textBlocks = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .filter { !$0.isEmpty }
        guard let text = textBlocks.max(by: { $0.count < $1.count }) else {
            throw CraftEngineError.emptyResponse
        }

        let usageDict = json["usage"] as? [String: Any] ?? [:]
        let usage = CraftUsage(
            inputTokens: usageDict["input_tokens"] as? Int ?? 0,
            cacheWriteTokens: usageDict["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadTokens: usageDict["cache_read_input_tokens"] as? Int ?? 0,
            outputTokens: usageDict["output_tokens"] as? Int ?? 0
        )
        print(String(format: "[CRAFT-COST] %@ · in=%d cacheWrite=%d cacheRead=%d out=%d · $%.4f",
                     model, usage.inputTokens, usage.cacheWriteTokens,
                     usage.cacheReadTokens, usage.outputTokens, usage.costUSD))
        await CraftCostLog.shared.record(usage)
        // Craft speaks its own HTTP — without this, craft runs are invisible
        // to the studio's "LLM calls" count and cache-health ratio.
        LLMCacheTelemetry.shared.record(
            response: LLMResponse(
                content: nil,
                toolCalls: [],
                inputTokens: usage.inputTokens,
                outputTokens: usage.outputTokens,
                cacheReadInputTokens: usage.cacheReadTokens,
                cacheCreationInputTokens: usage.cacheWriteTokens
            ),
            label: "craft"
        )

        return CraftCompletion(text: text, usage: usage)
    }

    static func requestBody(
        system: [[String: Any]],
        messages: [[String: Any]],
        jsonSchema: [String: Any]?,
        maxTokens: Int = defaultMaxTokens
    ) -> [String: Any] {
        var outputConfig: [String: Any] = ["effort": effort]
        if let jsonSchema {
            outputConfig["format"] = ["type": "json_schema", "schema": jsonSchema]
        }

        return [
            "model": model,
            "max_tokens": maxTokens,
            "thinking": ["type": "adaptive"],
            "output_config": outputConfig,
            "system": system,
            "messages": messages
        ]
    }

    // MARK: - Structured output schemas

    /// Structured-outputs constraints: every object closes additionalProperties
    /// and lists all properties as required — optionality is modeled as empty
    /// strings/arrays so the schema compiles once and caches.
    static var reviewSchema: [String: Any] {
        object([
            "formatRead": string("One line stating what you're reading, e.g. '9-slide carousel for Ben'."),
            "performanceRead": object([
                "tier": [
                    "type": "string",
                    "enum": ["top_quartile", "above_median", "around_median", "below_median"]
                ],
                "reasoning": string("Why this tier, grounded in the comparables and stats."),
                "evidence": array(object([
                    "comparable": string("Title of the comparable cited."),
                    "numbers": string("Its real numbers, e.g. '480K views · 6.1% ER'."),
                    "insight": string("What this comparable proves about the draft.")
                ]))
            ]),
            "slideNotes": array(object([
                "slide": ["type": "integer"],
                "failedTest": string("The craft test failed, by name."),
                "issue": string("The diagnosis, quoting the draft's actual line."),
                "fix": string("The specific fix — direction, not a rewrite."),
                "comparableQuote": string("Line from a comparable that does this beat well; empty if none.")
            ])),
            "topMoves": array(object([
                "move": string("The change, imperative."),
                "why": string("Expected impact, with evidence.")
            ])),
            "weakestBeat": object([
                "location": string("Where, e.g. 'Slide 1 hook'; empty when the draft has no weak beat worth riffing.", minLength: 0),
                "originalText": string("The draft's current text at that beat, verbatim.", minLength: 0),
                "microVariations": array(string("A worded variation in the client's voice."), minItems: 0)
            ]),
            "verdict": string("One closing paragraph, dinner-table voice: what this piece is one fix away from.")
        ])
    }

    static var riffSchema: [String: Any] {
        object([
            "beatLabel": string("The beat being riffed, e.g. 'Slide 3 — tension beat'."),
            "targetOriginalText": string("The draft's current text for this beat, copied VERBATIM — used to stage the replacement diff. Empty string when the beat is new or currently empty; never invent text the draft doesn't contain.", minLength: 0),
            "variations": array(object([
                "text": string("The variation, format-correct density, client's voice."),
                "mechanism": string("The mechanism in ≤6 words, e.g. 'curiosity gap via absence'."),
                "borrowedFrom": string("Which comparable's pattern this borrows; 'none' if original."),
                "numbers": string("That comparable's real numbers; empty if none.", minLength: 0)
            ]), minItems: 1),
            "bet": string("Which variation you'd bet on and why, one or two sentences.")
        ])
    }

    private static func object(_ properties: [String: Any]) -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": properties,
            "required": Array(properties.keys).sorted()
        ]
    }

    /// `minLength` and `minItems` are NOT supported by structured outputs.
    /// Constrained decoding enforces `type`, `enum`, `required` (key present) and
    /// `additionalProperties` — string-length and array-count assertions are
    /// silently ignored. The Python/TS SDKs strip unsupported constraints and
    /// validate client-side; this is raw HTTP, so emitting them bought nothing
    /// but false confidence (and would invite a 400 if validation ever tightens).
    ///
    /// The parameters stay because the call sites use them to document which
    /// fields may legitimately be empty. Real enforcement is `craftValidationIssue`.
    private static func string(_ description: String, minLength: Int = 1) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func array(_ items: [String: Any], minItems: Int = 0) -> [String: Any] {
        ["type": "array", "items": items]
    }
}

// MARK: - Cost log

/// Session-scoped spend ledger. Every craft call lands here; the runner reads
/// the rolling total for the receipt and settings can surface it later.
actor CraftCostLog {
    static let shared = CraftCostLog()

    private(set) var runs: [CraftUsage] = []

    var totalUSD: Double { runs.reduce(0) { $0 + $1.costUSD } }

    func record(_ usage: CraftUsage) {
        runs.append(usage)
        if runs.count > 200 { runs.removeFirst(runs.count - 200) }
    }
}
