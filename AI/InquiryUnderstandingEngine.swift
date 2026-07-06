// CosmoOS/AI/InquiryUnderstandingEngine.swift
// Lightweight live-synthesis engine for the Inquiry workspace stele.
// Produces a 4–5 sentence "current understanding" brief via ResearchService (Sonnet).
// Falls back to a deterministic heuristic when the LLM is unavailable.

import Foundation

actor InquiryUnderstandingEngine {
    static let shared = InquiryUnderstandingEngine()

    struct Input: Sendable {
        var deepDiveTitle: String?
        var deepDiveModel: String?
        var activeQuestionTitle: String
        var claims: [String]
        var speculativeClaims: [String]
        var evidence: [String]
        var counterevidence: [String]
        var recentCaptures: [String]
        var recentSourceTitles: [String]
        /// The roll-up: what this question's sub-questions have already
        /// established — nesting means answers COMPOSE upward, so the parent's
        /// brief absorbs its children's findings instead of re-opening them.
        var childFindings: [String] = []
    }

    struct Output: Sendable {
        var text: String
        var modelTier: String
    }

    private let systemPrompt = """
    You are Cosmo's research synthesizer. Write a single calm 4–5 sentence brief
    describing what is currently known about the active question, drawing on the
    supplied claims, evidence, and source notes. Hedge where the evidence is thin.
    When sub-questions have settled ground (listed under "Settled by sub-questions"),
    fold their conclusions into the brief as established — do not re-open them; the
    parent's answer COMPOSES from its children's answers. No bullets, no headings,
    no preamble. 120–180 words. End with the single most consequential open thread
    to investigate next.
    """

    func brief(_ input: Input) async -> Output {
        let prompt = buildUserPrompt(input)
        let response = try? await ResearchService.shared.analyze(
            prompt: prompt,
            systemPrompt: systemPrompt,
            tier: .strategist
        )
        let trimmed = (response ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return Output(text: trimmed, modelTier: AgentModelTier.strategist.rawValue)
        }
        return Output(text: heuristic(input), modelTier: "heuristic")
    }

    /// Stable signature used to skip regeneration when nothing material has changed.
    nonisolated func signature(for input: Input) -> String {
        var hasher = Hasher()
        hasher.combine(input.deepDiveTitle ?? "")
        hasher.combine(input.activeQuestionTitle)
        hasher.combine(input.claims.count)
        hasher.combine(input.speculativeClaims.count)
        hasher.combine(input.evidence.count)
        hasher.combine(input.counterevidence.count)
        hasher.combine(input.recentCaptures.count)
        hasher.combine(input.recentSourceTitles.count)
        hasher.combine(input.recentSourceTitles.first ?? "")
        hasher.combine(input.claims.first ?? "")
        hasher.combine(input.childFindings.count)
        hasher.combine(input.childFindings.first ?? "")
        return String(hasher.finalize())
    }

    // MARK: - Helpers

    private func buildUserPrompt(_ input: Input) -> String {
        var lines: [String] = []
        if let dd = input.deepDiveTitle, !dd.isEmpty {
            lines.append("Deep Dive: \(dd)")
        }
        if let model = input.deepDiveModel, !model.isEmpty {
            lines.append("Working model: \(model)")
        }
        lines.append("Active question: \(input.activeQuestionTitle)")
        if !input.claims.isEmpty {
            lines.append("Claims so far:")
            lines.append(contentsOf: input.claims.prefix(8).map { "- \($0)" })
        }
        if !input.speculativeClaims.isEmpty {
            lines.append("Speculative claims:")
            lines.append(contentsOf: input.speculativeClaims.prefix(6).map { "- \($0)" })
        }
        if !input.evidence.isEmpty {
            lines.append("Evidence:")
            lines.append(contentsOf: input.evidence.prefix(6).map { "- \($0)" })
        }
        if !input.counterevidence.isEmpty {
            lines.append("Counterevidence:")
            lines.append(contentsOf: input.counterevidence.prefix(4).map { "- \($0)" })
        }
        if !input.recentCaptures.isEmpty {
            lines.append("Recent captures:")
            lines.append(contentsOf: input.recentCaptures.prefix(6).map { "- \($0)" })
        }
        if !input.recentSourceTitles.isEmpty {
            lines.append("Source titles (recent):")
            lines.append(contentsOf: input.recentSourceTitles.prefix(5).map { "- \($0)" })
        }
        if !input.childFindings.isEmpty {
            lines.append("Settled by sub-questions (fold in as established, do not re-open):")
            lines.append(contentsOf: input.childFindings.prefix(6).map { "- \($0)" })
        }
        lines.append("")
        lines.append("Write the brief now.")
        return lines.joined(separator: "\n")
    }

    private func heuristic(_ input: Input) -> String {
        let claimCount = input.claims.count + input.speculativeClaims.count
        let evCount = input.evidence.count + input.counterevidence.count
        var s = "Exploration of \"\(input.activeQuestionTitle)\" is "
        if claimCount + evCount == 0 {
            s += "just beginning — no claims or evidence have been routed yet."
        } else {
            s += "in progress with \(claimCount) claim\(claimCount == 1 ? "" : "s") "
            s += "and \(evCount) piece\(evCount == 1 ? "" : "s") of evidence captured so far."
        }
        if let first = (input.claims.first ?? input.speculativeClaims.first), !first.isEmpty {
            s += " The most prominent thread is: \(first)"
        }
        s += " A few sources have been opened (\(input.recentSourceTitles.count) so far). Synthesis will sharpen as more is captured."
        return s
    }
}
