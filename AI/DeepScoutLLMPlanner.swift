// CosmoOS/AI/DeepScoutLLMPlanner.swift
// The Deep Scout brain: one LLM call turns the branch's research profile into
// human-quality search queries across source lanes — the way a person would
// actually search YouTube, podcast apps, book catalogs, and scholarly indexes.
// It replaces the keyword-heuristic DeepScoutIntentPlanner on the primary
// path; the heuristics survive only as the offline fallback.

import Foundation

actor DeepScoutLLMPlanner {
    static let shared = DeepScoutLLMPlanner()

    /// Deep Scout runs in the background with visible per-provider progress,
    /// so a smarter, slower plan is the right trade — but the whole scout
    /// shouldn't stall on one hung call.
    private let timeoutNanoseconds: UInt64 = 18_000_000_000

    /// Plan the scout run. Returns nil on failure/offline — the caller falls
    /// back to DeepScoutIntentPlanner's template queries.
    func plan(
        for profile: InquiryBranchResearchProfile,
        taste: DeepScoutTasteProfile
    ) async -> DeepScoutPlan? {
        let prompt = Self.buildPrompt(profile: profile, taste: taste)
        let raw = await withTimeout {
            try await ResearchService.shared.analyze(
                prompt: prompt,
                systemPrompt: Self.systemPrompt,
                tier: .strategist,
                maxTokens: 1400
            )
        }
        guard let raw, let plan = Self.parse(raw) else { return nil }
        return plan
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
    You are Cosmo's Deep Scout planner. A user is researching a question inside a topic. Your job is \
    to write the search queries a smart, modern learner would actually type — across YouTube, podcast \
    directories, book catalogs, archives, and (only when warranted) scholarly indexes — so the results \
    feel hand-picked, not scraped.

    THE MODERN LEARNING BIAS: today's best explanations of most non-clinical questions live with \
    practitioners and synthesizers — long-form podcasts, YouTube lectures and interviews, and books — \
    not in journals. Default the plan toward those lanes. Reach for scholarly/clinical lanes ONLY when \
    the question itself is empirical ("does X actually work", dosage, safety, physiology) — and even \
    then keep at least two podcast/video queries in the plan.

    HOW TO WRITE EACH QUERY (this is the core skill):
    1. SEARCH LIKE A PERSON, NOT A LIBRARIAN. People type 2–6 punchy words, not sentences.
       Question: "Why do humans push themselves to their limits?"
       BAD:  "humans pushing themselves to their limits psychological analysis"
       GOOD: "why we seek hard challenges podcast", "voluntary hardship interview",
             "David Goggins pushing limits", "endurance psychology lecture"
    2. NAME NAMES. The highest-yield video/podcast queries pair the topic with a person or show that
       covers it. Use the user's FAVORITE CREATORS list when the topic plausibly overlaps their beat;
       add well-known voices you know cover this territory (authors of the classic books on it,
       hosts who interview those authors). One creator per query, max.
    3. VARY THE ANGLE ACROSS QUERIES — never write five rewordings of one search. Cover:
       the direct question · a named creator take · the classic book(s) · an interview/podcast angle ·
       a practice/how-to angle (when the topic is actionable) · the strongest opposing view.
    4. FORMAT WORDS EARN THEIR PLACE: append "podcast", "interview", "lecture", "audiobook",
       "explained" only on queries whose lane wants that format.
    5. NO FILLER TOKENS: drop stopwords, years, and the user's own jargon that a search engine
       wouldn't know.

    LANES (use raw values): "primaryText" (foundational/original texts), "deepRead" (books),
    "teacherLecture" (YouTube videos + podcast episodes), "practiceGuide" (how-to/protocols),
    "scholarlyContext" (papers/reviews), "clinicalEvidence" (trials/meta-analyses),
    "webResource" (essays, blogs, everything else).

    PROVIDERS (use raw values): "youtube", "podcast", "googleBooks", "openLibrary",
    "internetArchive", "openAlex", "crossref", "semanticScholar", "pubMed", "web".
    Match providers to the lane: teacherLecture → youtube/podcast; deepRead → googleBooks/openLibrary;
    primaryText → internetArchive/openLibrary/web; practiceGuide → web/youtube;
    scholarlyContext → openAlex/crossref/semanticScholar; clinicalEvidence → openAlex/semanticScholar/pubMed;
    webResource → web.

    INTENTS (use raw values): "conceptExploration", "clinicalEvidence", "mechanismScience",
    "practiceTechnique", "historicalLineage", "philosophicalOrientation", "sourceSurvey".

    HARD RULES:
    1. 6–10 queries total. At least 3 must target the "teacherLecture" lane (youtube/podcast).
    2. Every query ≤ 7 words. No punctuation except quotes are forbidden too — plain words only.
    3. At most 2 scholarly/clinical queries, and ZERO unless the question is genuinely empirical.
    4. Use a FAVORITE CREATOR in 1–3 queries when plausible for the topic; never force an
       irrelevant creator onto a topic outside their beat.
    5. Never include creators from the AVOIDED list.
    6. Respond with VALID JSON only. No prose, no markdown fences.

    WORKED EXAMPLE:
    Topic: "Self-Improvement" · Question: "Why do humans push themselves to their limits?"
    Favorite creators: Alex Hormozi, Chris Williamson (Modern Wisdom), Huberman Lab
    → {"intent":"conceptExploration","queries":[
      {"query":"why we seek hard challenges","lane":"teacherLecture","providers":["youtube","podcast"]},
      {"query":"Alex Hormozi doing hard things","lane":"teacherLecture","providers":["youtube"]},
      {"query":"Chris Williamson voluntary hardship","lane":"teacherLecture","providers":["youtube","podcast"]},
      {"query":"Huberman stress growth mindset","lane":"teacherLecture","providers":["youtube","podcast"]},
      {"query":"endure Alex Hutchinson","lane":"deepRead","providers":["googleBooks","openLibrary"]},
      {"query":"psychology of pushing limits book","lane":"deepRead","providers":["googleBooks","openLibrary"]},
      {"query":"hormesis stress adaptation explained","lane":"webResource","providers":["web"]},
      {"query":"post traumatic growth research review","lane":"scholarlyContext","providers":["openAlex","semanticScholar"]}
    ]}

    OUTPUT SCHEMA:
    {"intent":"<intent raw value>","queries":[{"query":"<2-7 words>","lane":"<lane raw value>","providers":["<provider raw value>"]}]}
    """

    static func buildPrompt(
        profile: InquiryBranchResearchProfile,
        taste: DeepScoutTasteProfile
    ) -> String {
        var lines: [String] = []
        if let title = profile.deepDiveTitle {
            lines.append("TOPIC: \(title)")
        }
        lines.append("QUESTION: \(profile.sourceQuery ?? profile.activeQuestionTitle)")
        if profile.sourceQuery != nil {
            lines.append("(the user typed this focus themselves — honor it over the question)")
        }
        if !profile.ancestorTitles.isEmpty {
            lines.append("PARENT QUESTIONS: \(profile.ancestorTitles.joined(separator: " · "))")
        }
        if !profile.claims.isEmpty {
            lines.append("\nWHAT THE USER BELIEVES SO FAR (angle the queries at what's still open):")
            for claim in profile.claims.prefix(5) {
                lines.append("- \(claim.prefix(160))")
            }
        }
        if !taste.favoriteCreators.isEmpty {
            let names = taste.favoriteCreators.map { "\($0.creator) (\($0.imports) imports)" }
            lines.append("\nFAVORITE CREATORS (learned from what this user actually imports):")
            lines.append(names.joined(separator: ", "))
        }
        if !taste.avoidedCreators.isEmpty {
            lines.append("AVOIDED CREATORS (the user keeps dismissing these — never query them):")
            lines.append(taste.avoidedCreators.map(\.creator).joined(separator: ", "))
        }
        lines.append("\nReturn the plan JSON now.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Parsing

    static func parse(_ raw: String) -> DeepScoutPlan? {
        guard let dict = ConceptResolver.jsonObject(from: raw),
              let queryEntries = dict["queries"] as? [[String: Any]] else { return nil }
        let intent = (dict["intent"] as? String).flatMap(InquiryResearchIntent.init(rawValue:))
            ?? .conceptExploration

        var queries: [DeepScoutQuery] = []
        var seen: Set<String> = []
        for entry in queryEntries.prefix(10) {
            guard let query = (entry["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !query.isEmpty,
                  let lane = (entry["lane"] as? String).flatMap(InquirySourceLane.init(rawValue:)) else { continue }
            let providers = ((entry["providers"] as? [String]) ?? [])
                .compactMap(InquirySourceProvider.init(rawValue:))
            // Collapse whitespace before comparing — the model sometimes emits
            // the same search twice with only spacing/case differences.
            let normalized = InquiryPlacementEngine.normalized(query)
                .split(separator: " ")
                .joined(separator: " ")
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            queries.append(DeepScoutQuery(
                query: query,
                lane: lane,
                providers: providers.isEmpty ? Self.defaultProviders(for: lane) : providers
            ))
        }
        guard queries.count >= 3 else { return nil }
        return DeepScoutPlan(intent: intent, queries: queries)
    }

    static func defaultProviders(for lane: InquirySourceLane) -> [InquirySourceProvider] {
        switch lane {
        case .teacherLecture: return [.youtube, .podcast]
        case .deepRead: return [.googleBooks, .openLibrary]
        case .primaryText: return [.internetArchive, .openLibrary, .web]
        case .practiceGuide: return [.web, .youtube]
        case .scholarlyContext: return [.openAlex, .crossref, .semanticScholar]
        case .clinicalEvidence: return [.openAlex, .semanticScholar, .pubMed]
        case .localLibrary: return [.local]
        case .webResource: return [.web]
        }
    }
}
