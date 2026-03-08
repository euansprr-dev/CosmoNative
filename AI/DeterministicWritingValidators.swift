// CosmoOS/AI/DeterministicWritingValidators.swift
// Instant mechanical validators for hard lesson enforcement.
// Run after handleWriteDraft() — violations injected into conversation loop for self-correction.
// March 2026

import Foundation

// MARK: - Violation Model

struct WritingViolation: CustomStringConvertible {
    let lessonID: UUID?
    let rule: String
    let offendingSnippet: String
    let suggestion: String

    var description: String {
        var desc = "VIOLATION: \(rule)"
        if !offendingSnippet.isEmpty {
            desc += "\n  FOUND: \"\(offendingSnippet)\""
        }
        if !suggestion.isEmpty {
            desc += "\n  FIX: \(suggestion)"
        }
        return desc
    }
}

// MARK: - Validator Protocol

protocol WritingValidator {
    /// Human-readable name of this validator
    var name: String { get }

    /// Check a draft for violations. Returns empty array if compliant.
    /// - Parameters:
    ///   - draft: The full draft text
    ///   - format: Content format (carousel, reel, thread, etc.) for format-aware checks
    ///   - hardRules: The hard rules to check against (for rule-specific validators)
    func validate(draft: String, format: String?, hardRules: [InferredLesson]) -> [WritingViolation]
}

// MARK: - Cadence Validator

/// Detects repetitive short-sentence fragment chains (X. Y. Z. pattern).
/// Skipped for carousel/slide formats where punchy fragments are the desired style.
struct CadenceValidator: WritingValidator {
    let name = "Cadence"

    /// Minimum consecutive short sentences to flag as a pattern
    private let minChain = 4
    /// Maximum word count to be considered a "short fragment"
    private let maxFragmentWords = 5

    func validate(draft: String, format: String?, hardRules: [InferredLesson]) -> [WritingViolation] {
        // Skip for carousel/slide formats — short punchy sentences are intentional
        let skipFormats = ["carousel", "instagram_carousel", "instagramCarousel"]
        if let format = format, skipFormats.contains(format.lowercased()) {
            return []
        }

        let sentences = splitIntoSentences(draft)
        var violations: [WritingViolation] = []
        var chainStart = 0
        var chainLength = 0

        for (i, sentence) in sentences.enumerated() {
            let wordCount = sentence.split(separator: " ").count
            if wordCount <= maxFragmentWords && wordCount > 0 {
                if chainLength == 0 { chainStart = i }
                chainLength += 1
            } else {
                if chainLength >= minChain {
                    let chain = sentences[chainStart..<(chainStart + chainLength)]
                    let snippet = chain.joined(separator: " ")
                    violations.append(WritingViolation(
                        lessonID: nil,
                        rule: "Avoid repetitive staccato cadence — \(chainLength) consecutive short fragments detected",
                        offendingSnippet: String(snippet.prefix(200)),
                        suggestion: "Vary sentence length. Mix short punchy sentences with longer flowing ones for rhythm."
                    ))
                }
                chainLength = 0
            }
        }

        // Check trailing chain
        if chainLength >= minChain {
            let chain = sentences[chainStart..<(chainStart + chainLength)]
            let snippet = chain.joined(separator: " ")
            violations.append(WritingViolation(
                lessonID: nil,
                rule: "Avoid repetitive staccato cadence — \(chainLength) consecutive short fragments detected",
                offendingSnippet: String(snippet.prefix(200)),
                suggestion: "Vary sentence length. Mix short punchy sentences with longer flowing ones for rhythm."
            ))
        }

        return violations
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        // Split on sentence-ending punctuation, keeping the result clean
        let pattern = "[.!?]+"
        let components = text.components(separatedBy: "\n")
            .flatMap { line -> [String] in
                guard let regex = try? NSRegularExpression(pattern: pattern) else {
                    return [line]
                }
                var sentences: [String] = []
                var lastEnd = line.startIndex
                let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
                regex.enumerateMatches(in: line, range: nsRange) { match, _, _ in
                    guard let match = match, let range = Range(match.range, in: line) else { return }
                    let sentence = String(line[lastEnd..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sentence.isEmpty {
                        sentences.append(sentence)
                    }
                    lastEnd = range.upperBound
                }
                // Trailing text without punctuation
                let remaining = String(line[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !remaining.isEmpty {
                    sentences.append(remaining)
                }
                return sentences
            }
        return components.filter { !$0.isEmpty }
    }
}

// MARK: - Banned Phrase Validator

/// Checks for phrases that appear in hard rules with clear "never use" / "avoid" / "don't" directives.
/// Extracts banned phrases from rule text patterns like "Never use X", "Avoid X", "Don't say X".
struct BannedPhraseValidator: WritingValidator {
    let name = "BannedPhrases"

    func validate(draft: String, format: String?, hardRules: [InferredLesson]) -> [WritingViolation] {
        var violations: [WritingViolation] = []
        let lowerDraft = draft.lowercased()

        for rule in hardRules {
            let bannedPhrases = extractBannedPhrases(from: rule.rule)
                + extractBannedPhrases(from: rule.optimizedInstruction ?? "")

            for phrase in bannedPhrases {
                let lowerPhrase = phrase.lowercased()
                guard lowerPhrase.count >= 3 else { continue }  // Skip very short phrases

                if lowerDraft.contains(lowerPhrase) {
                    // Find the offending context
                    if let range = lowerDraft.range(of: lowerPhrase) {
                        let start = lowerDraft.index(range.lowerBound, offsetBy: -30, limitedBy: lowerDraft.startIndex) ?? lowerDraft.startIndex
                        let end = lowerDraft.index(range.upperBound, offsetBy: 30, limitedBy: lowerDraft.endIndex) ?? lowerDraft.endIndex
                        let snippet = String(draft[start..<end])

                        violations.append(WritingViolation(
                            lessonID: rule.id,
                            rule: "Banned phrase detected: \"\(phrase)\"",
                            offendingSnippet: "...\(snippet)...",
                            suggestion: "Remove or rephrase to avoid \"\(phrase)\". Rule: \(rule.rule)"
                        ))
                    }
                }
            }
        }

        return violations
    }

    /// Extract phrases from "never use X", "avoid X", "don't use X" patterns
    private func extractBannedPhrases(from text: String) -> [String] {
        var phrases: [String] = []
        let patterns = [
            "never use \"([^\"]+)\"",
            "avoid \"([^\"]+)\"",
            "don't use \"([^\"]+)\"",
            "don't say \"([^\"]+)\"",
            "never say \"([^\"]+)\"",
            "never write \"([^\"]+)\"",
            "ban(?:ned)?:?\\s*\"([^\"]+)\"",
            "BAD:\\s*\"?([^\"\\n]+)\"?"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: nsRange) {
                if match.numberOfRanges >= 2,
                   let range = Range(match.range(at: 1), in: text) {
                    let phrase = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if phrase.count >= 3 && phrase.count <= 100 {
                        phrases.append(phrase)
                    }
                }
            }
        }

        return phrases
    }
}

// MARK: - Validator Runner

/// Runs all deterministic validators against a draft and returns aggregate violations.
@MainActor
enum DeterministicWritingValidatorRunner {

    /// All registered validators
    private static let validators: [WritingValidator] = [
        CadenceValidator(),
        BannedPhraseValidator()
    ]

    /// Run all validators against a draft. Returns violations (empty = compliant).
    static func validate(
        draft: String,
        format: String?,
        hardRules: [InferredLesson]
    ) -> [WritingViolation] {
        guard !draft.isEmpty, !hardRules.isEmpty else { return [] }

        var allViolations: [WritingViolation] = []

        for validator in validators {
            let violations = validator.validate(draft: draft, format: format, hardRules: hardRules)
            allViolations.append(contentsOf: violations)
        }

        return allViolations
    }

    /// Format violations as a system message for injection into the writing engine conversation loop.
    /// Returns nil if no violations.
    static func formatViolationMessage(_ violations: [WritingViolation]) -> String? {
        guard !violations.isEmpty else { return nil }

        var message = "[COMPLIANCE CHECK — HARD RULE VIOLATIONS DETECTED]\n\n"
        message += "The draft violates \(violations.count) hard rule(s). You MUST fix these before presenting the final draft.\n\n"

        for (i, violation) in violations.enumerated() {
            message += "\(i + 1). \(violation)\n\n"
        }

        message += "Rewrite the violating sections to comply with these rules. Do NOT present the draft until all violations are resolved."

        return message
    }
}
