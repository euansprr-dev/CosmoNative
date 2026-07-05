// CosmoOS/AI/DeepScoutLLMRanker.swift
// Second stage of Deep Scout ranking: after the heuristic prefilter (topic
// gate, junk-title penalty, dedupe) one LLM call reads the surviving
// candidates and scores how genuinely useful each would be for THIS question,
// biased toward synthesizers and practitioners for non-empirical questions.
// On failure the heuristic order stands — the scout never blocks on the model.

import Foundation

actor DeepScoutLLMRanker {
    static let shared = DeepScoutLLMRanker()

    /// How many prefiltered candidates ride the ranking call.
    static let maxCandidates = 32

    private let timeoutNanoseconds: UInt64 = 22_000_000_000

    struct Judgment: Sendable, Equatable {
        var score: Double        // 0–1
        var reason: String?
    }

    /// Judge candidates for usefulness. Returns judgments keyed by candidate id;
    /// empty on failure (caller keeps heuristic scores).
    func judge(
        candidates: [InquirySourceCandidate],
        profile: InquiryBranchResearchProfile,
        intent: InquiryResearchIntent,
        taste: DeepScoutTasteProfile
    ) async -> [String: Judgment] {
        let batch = Array(candidates.prefix(Self.maxCandidates))
        guard batch.count >= 4 else { return [:] }   // Too few to be worth a call.
        let prompt = Self.buildPrompt(candidates: batch, profile: profile, intent: intent, taste: taste)
        let raw = await withTimeout {
            try await ResearchService.shared.analyze(
                prompt: prompt,
                systemPrompt: Self.systemPrompt,
                tier: .strategist,
                maxTokens: 260 + batch.count * 60
            )
        }
        guard let raw else { return [:] }
        return Self.parse(raw, candidates: batch)
    }

    private func withTimeout(_ work: @escaping @Sendable () async throws -> String) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { try? await work() }
            group.addTask { [timeoutNanoseconds] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Prompt

    static let systemPrompt = """
    You are Cosmo's Deep Scout judge. You receive search-result candidates gathered for a research \
    question and score how useful each would genuinely be to a curious, intelligent learner working \
    on that exact question.

    SCORING (0–100):
    - 85–100: directly about the question, from a credible teacher/synthesizer/source the learner
      would thank you for. A known long-form podcast or lecture squarely on the question belongs here.
    - 60–84: clearly relevant and worth a look — right topic, decent source, or a favorite creator
      adjacent to the question.
    - 30–59: related but oblique — background material, tangent, or weak source.
    - 0–29: off-topic, spam-shaped, catalog junk, a random short video, or academic material that
      merely shares keywords with the question.

    JUDGING RULES:
    1. THE QUESTION IS THE YARDSTICK. "Shares words with the question" is not relevance — a paper on
       "Marshall Islands climate limits" is junk for a question about humans pushing their limits.
    2. For non-empirical questions, favor synthesizers and practitioners (podcasts, lectures,
       respected books) over papers; for empirical questions (does it work, dosage, safety), favor
       reviews and trials — but a great practitioner interview still scores well.
    3. FAVORITE CREATORS get the benefit of the doubt when on-topic (+10 spirit), but an off-topic
       favorite is still off-topic.
    4. Prefer depth over clickbait: an hour-long interview or a classic book beats a 60-second
       motivation edit. Penalize obvious motivation-spam titles (ALL CAPS, "MUST WATCH").
    5. Score every candidate you were given, once each, by its "i" index.
    6. Respond with VALID JSON only. No prose, no markdown fences.

    OUTPUT SCHEMA:
    {"rankings":[{"i":<index>,"score":<0-100>,"reason":"<≤12 words, why a learner should care>"}]}
    """

    static func buildPrompt(
        candidates: [InquirySourceCandidate],
        profile: InquiryBranchResearchProfile,
        intent: InquiryResearchIntent,
        taste: DeepScoutTasteProfile
    ) -> String {
        var lines: [String] = []
        if let title = profile.deepDiveTitle {
            lines.append("TOPIC: \(title)")
        }
        lines.append("QUESTION: \(profile.sourceQuery ?? profile.activeQuestionTitle)")
        lines.append("QUESTION TYPE: \(intent.rawValue)")
        if !taste.favoriteCreators.isEmpty {
            lines.append("FAVORITE CREATORS: \(taste.favoriteCreators.map(\.creator).joined(separator: ", "))")
        }
        lines.append("\nCANDIDATES:")
        for (index, candidate) in candidates.enumerated() {
            var parts: [String] = []
            parts.append("[\(index)] \(candidate.title.prefix(110))")
            if let creator = DeepScoutTasteStore.creatorName(for: candidate) {
                parts.append("by \(creator.prefix(40))")
            }
            parts.append("(\(candidate.provider.displayName)\(candidate.publishedDate.map { ", \($0)" } ?? ""))")
            if let abstract = candidate.abstract, !abstract.isEmpty {
                parts.append("— \(abstract.prefix(140))")
            }
            lines.append(parts.joined(separator: " "))
        }
        lines.append("\nReturn the rankings JSON now.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Parsing

    static func parse(_ raw: String, candidates: [InquirySourceCandidate]) -> [String: Judgment] {
        guard let dict = ConceptResolver.jsonObject(from: raw),
              let rankings = dict["rankings"] as? [[String: Any]] else { return [:] }
        var judgments: [String: Judgment] = [:]
        for entry in rankings {
            guard let index = entry["i"] as? Int,
                  candidates.indices.contains(index) else { continue }
            let rawScore: Double
            if let value = entry["score"] as? Double {
                rawScore = value
            } else if let value = entry["score"] as? Int {
                rawScore = Double(value)
            } else {
                continue
            }
            let id = candidates[index].id
            guard judgments[id] == nil else { continue }
            judgments[id] = Judgment(
                score: max(0, min(1, rawScore / 100)),
                reason: (entry["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
        }
        // A response that judged under half the batch is a malformed answer,
        // not a ranking — better to keep the heuristic order.
        guard judgments.count * 2 >= candidates.count else { return [:] }
        return judgments
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
