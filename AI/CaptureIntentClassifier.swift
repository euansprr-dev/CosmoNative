// CosmoOS/AI/CaptureIntentClassifier.swift
// Heuristic capture intent detection for Inquiry rows.

import Foundation

struct CaptureIntent: Sendable, Equatable {
    var kind: ExtractKind
    var confidence: Double
    var reason: String
}

actor CaptureIntentClassifier {
    static let shared = CaptureIntentClassifier()

    func classify(text: String, context: InquiryPlacementEngine.Context? = nil) -> CaptureIntent {
        Self.classifyHeuristic(text: text, context: context)
    }

    nonisolated static func classifyHeuristic(
        text: String,
        context: InquiryPlacementEngine.Context? = nil
    ) -> CaptureIntent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard !trimmed.isEmpty else {
            return CaptureIntent(kind: .note, confidence: 0.0, reason: "Empty capture")
        }

        if InquiryDockPrefixParser.looksLikeURL(trimmed) {
            return CaptureIntent(kind: .reference, confidence: 0.9, reason: "Looks like a URL")
        }

        if isQuestion(lower) {
            return CaptureIntent(kind: .question, confidence: 0.9, reason: "Question phrasing")
        }

        if hasPrefix(in: lower, prefixes: speculativePrefixes) {
            return CaptureIntent(kind: .speculativeClaim, confidence: 0.75, reason: "Speculative claim phrasing")
        }

        if containsAny(lower, terms: practiceTerms) {
            return CaptureIntent(kind: .practice, confidence: 0.6, reason: "Practice or protocol language")
        }

        if isDeclarativeClaim(trimmed) {
            return CaptureIntent(kind: .claim, confidence: 0.6, reason: "Declarative assertion")
        }

        return CaptureIntent(kind: .note, confidence: 0.4, reason: "Default note")
    }

    private nonisolated static let questionPrefixes: [String] = [
        "what", "how", "why", "when", "where", "who", "is", "are",
        "does", "do", "should", "could", "would", "can", "will"
    ]

    private nonisolated static let speculativePrefixes: [String] = [
        "i think", "it seems", "maybe", "perhaps", "likely", "might", "could be"
    ]

    private nonisolated static let practiceTerms: [String] = [
        "should", "recommend", "protocol", "practice", "technique", "breathe",
        "breathing exercise", "inhale", "exhale"
    ]

    private nonisolated static func isQuestion(_ lower: String) -> Bool {
        if lower.hasSuffix("?") { return true }
        let firstToken = lower
            .split(whereSeparator: { !$0.isLetter })
            .first
            .map(String.init) ?? ""
        return questionPrefixes.contains(firstToken) && lower.contains("?")
    }

    private nonisolated static func hasPrefix(in lower: String, prefixes: [String]) -> Bool {
        prefixes.contains { lower == $0 || lower.hasPrefix("\($0) ") }
    }

    private nonisolated static func containsAny(_ lower: String, terms: [String]) -> Bool {
        terms.contains { term in
            lower == term || lower.contains(" \(term) ") || lower.hasPrefix("\(term) ") || lower.hasSuffix(" \(term)")
        }
    }

    private nonisolated static func isDeclarativeClaim(_ text: String) -> Bool {
        let lower = text.lowercased()
        guard text.count >= 24, !lower.hasSuffix("?") else { return false }
        if containsAny(lower, terms: ["is", "are", "improves", "increases", "reduces", "causes", "modulates", "predicts"]) {
            return true
        }
        let tokens = lower.split(whereSeparator: { !$0.isLetter })
        return tokens.count >= 5 && !hasPrefix(in: lower, prefixes: ["note", "remember", "todo"])
    }
}
