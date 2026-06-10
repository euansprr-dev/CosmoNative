// CosmoOS/AI/DeepScoutIntentPlanner.swift

import Foundation

struct DeepScoutQuery: Sendable, Equatable {
    var query: String
    var lane: InquirySourceLane
    var providers: [InquirySourceProvider]
}

struct DeepScoutPlan: Sendable, Equatable {
    var intent: InquiryResearchIntent
    var queries: [DeepScoutQuery]
}

enum DeepScoutIntentPlanner {
    static func intent(for profile: InquiryBranchResearchProfile) -> InquiryResearchIntent {
        let text = [
            profile.sourceQuery,
            profile.activeQuestionTitle,
            profile.ancestorTitles.joined(separator: " "),
            profile.claims.joined(separator: " ")
        ].compactMap { $0 }.joined(separator: " ").lowercased()

        if containsAny(text, clinicalTerms) {
            return .clinicalEvidence
        }
        if containsAny(text, mechanismTerms) {
            return .mechanismScience
        }
        if containsAny(text, practiceTerms) {
            return .practiceTechnique
        }
        if containsAny(text, lineageTerms) {
            return .historicalLineage
        }
        if containsAny(text, philosophicalTerms) {
            return .philosophicalOrientation
        }
        if containsAny(text, surveyTerms) {
            return .sourceSurvey
        }
        return .conceptExploration
    }

    static func plan(
        for profile: InquiryBranchResearchProfile,
        mode: InquirySourceSearchMode
    ) -> DeepScoutPlan {
        let intent = intent(for: profile)
        let focus = normalizedFocus(for: profile)
        guard mode == .deepScout else {
            return DeepScoutPlan(
                intent: intent,
                queries: [
                    DeepScoutQuery(
                        query: focus,
                        lane: .webResource,
                        providers: [.local, .openAlex, .crossref]
                    )
                ]
            )
        }

        let anchors = anchorSeed(for: profile, focus: focus)
        let queries: [DeepScoutQuery]
        switch intent {
        case .clinicalEvidence:
            queries = clinicalQueries(focus: focus)
        case .mechanismScience:
            queries = mechanismQueries(focus: focus)
        case .practiceTechnique:
            queries = practiceQueries(focus: focus, anchors: anchors)
        case .historicalLineage:
            queries = lineageQueries(focus: focus, anchors: anchors)
        case .philosophicalOrientation:
            queries = philosophyQueries(focus: focus, anchors: anchors)
        case .sourceSurvey:
            queries = surveyQueries(focus: focus, anchors: anchors)
        case .conceptExploration:
            queries = conceptQueries(focus: focus, anchors: anchors)
        }

        return DeepScoutPlan(intent: intent, queries: deduped(queries))
    }

    /// Up to two deep-dive anchor terms not already present in the focus —
    /// grounds generic query templates in the topic's own vocabulary.
    private static func anchorSeed(for profile: InquiryBranchResearchProfile, focus: String) -> String {
        let focusTokens = InquirySourceRecommendationEngine.significantTokens(focus)
        let fresh = profile.anchorTerms
            .subtracting(focusTokens)
            .sorted()
            .prefix(2)
        return fresh.joined(separator: " ")
    }

    private static func seeded(_ base: String, _ anchors: String) -> String {
        anchors.isEmpty ? base : "\(base) \(anchors)"
    }

    private static func conceptQueries(focus: String, anchors: String) -> [DeepScoutQuery] {
        [
            DeepScoutQuery(
                query: seeded("\(focus) meaning primary text", anchors),
                lane: .primaryText,
                providers: [.web, .internetArchive]
            ),
            DeepScoutQuery(
                query: seeded("\(focus) book", anchors),
                lane: .deepRead,
                providers: [.googleBooks, .openLibrary, .internetArchive]
            ),
            DeepScoutQuery(
                query: "\(focus) classic text translation commentary",
                lane: .primaryText,
                providers: [.internetArchive, .web, .openLibrary]
            ),
            DeepScoutQuery(
                query: seeded("\(focus) philosophy tradition", anchors),
                lane: .scholarlyContext,
                providers: [.openAlex, .crossref, .semanticScholar, .web]
            ),
            DeepScoutQuery(
                query: condensed(focus),
                lane: .teacherLecture,
                providers: [.youtube]
            ),
            DeepScoutQuery(
                query: "\(condensed(focus)) podcast",
                lane: .teacherLecture,
                providers: [.youtube, .podcast]
            ),
            DeepScoutQuery(
                query: "\(focus) scholarly overview review history",
                lane: .scholarlyContext,
                providers: [.openAlex, .crossref, .semanticScholar]
            )
        ]
    }

    private static func clinicalQueries(focus: String) -> [DeepScoutQuery] {
        [
            DeepScoutQuery(
                query: "\(focus) systematic review meta-analysis",
                lane: .clinicalEvidence,
                providers: [.openAlex, .crossref, .semanticScholar, .pubMed]
            ),
            DeepScoutQuery(
                query: "\(focus) randomized controlled trial clinical trial",
                lane: .clinicalEvidence,
                providers: [.openAlex, .semanticScholar, .pubMed]
            ),
            DeepScoutQuery(
                query: "\(focus) adverse effects contraindications",
                lane: .clinicalEvidence,
                providers: [.openAlex, .crossref, .pubMed]
            ),
            DeepScoutQuery(
                query: condensed(focus),
                lane: .teacherLecture,
                providers: [.youtube]
            ),
            DeepScoutQuery(
                query: "\(condensed(focus)) podcast",
                lane: .teacherLecture,
                providers: [.youtube, .podcast]
            )
        ]
    }

    private static func mechanismQueries(focus: String) -> [DeepScoutQuery] {
        [
            DeepScoutQuery(
                query: "\(focus) physiology mechanism review",
                lane: .scholarlyContext,
                providers: [.openAlex, .crossref, .semanticScholar]
            ),
            DeepScoutQuery(
                query: "\(focus) nervous system respiration mechanism",
                lane: .scholarlyContext,
                providers: [.openAlex, .semanticScholar, .pubMed]
            ),
            DeepScoutQuery(
                query: "\(focus) book physiology",
                lane: .deepRead,
                providers: [.googleBooks, .openLibrary]
            ),
            DeepScoutQuery(
                query: condensed(focus),
                lane: .teacherLecture,
                providers: [.youtube]
            ),
            DeepScoutQuery(
                query: "\(condensed(focus)) podcast",
                lane: .teacherLecture,
                providers: [.youtube, .podcast]
            )
        ]
    }

    private static func practiceQueries(focus: String, anchors: String) -> [DeepScoutQuery] {
        [
            DeepScoutQuery(
                query: "\(focus) traditional practice guide",
                lane: .practiceGuide,
                providers: [.web, .openLibrary, .internetArchive]
            ),
            DeepScoutQuery(
                query: seeded("\(focus) book practice technique", anchors),
                lane: .deepRead,
                providers: [.googleBooks, .openLibrary]
            ),
            DeepScoutQuery(
                query: "\(condensed(focus)) technique",
                lane: .teacherLecture,
                providers: [.youtube]
            ),
            DeepScoutQuery(
                query: "\(condensed(focus)) podcast",
                lane: .teacherLecture,
                providers: [.youtube, .podcast]
            ),
            DeepScoutQuery(
                query: "\(focus) contraindications safety",
                lane: .clinicalEvidence,
                providers: [.openAlex, .crossref, .pubMed]
            )
        ]
    }

    private static func lineageQueries(focus: String, anchors: String) -> [DeepScoutQuery] {
        [
            DeepScoutQuery(
                query: "\(focus) history lineage origin",
                lane: .scholarlyContext,
                providers: [.openAlex, .crossref, .semanticScholar]
            ),
            DeepScoutQuery(
                query: "\(focus) primary text translation commentary",
                lane: .primaryText,
                providers: [.internetArchive, .openLibrary, .web]
            ),
            DeepScoutQuery(
                query: seeded("\(focus) book history", anchors),
                lane: .deepRead,
                providers: [.googleBooks, .openLibrary]
            ),
            DeepScoutQuery(
                query: "\(condensed(focus)) history",
                lane: .teacherLecture,
                providers: [.youtube]
            ),
            DeepScoutQuery(
                query: "\(condensed(focus)) podcast",
                lane: .teacherLecture,
                providers: [.youtube, .podcast]
            )
        ]
    }

    private static func philosophyQueries(focus: String, anchors: String) -> [DeepScoutQuery] {
        [
            DeepScoutQuery(
                query: seeded("\(focus) philosophy", anchors),
                lane: .scholarlyContext,
                providers: [.openAlex, .crossref, .semanticScholar, .web]
            ),
            DeepScoutQuery(
                query: "\(focus) primary text commentary",
                lane: .primaryText,
                providers: [.internetArchive, .openLibrary, .web]
            ),
            DeepScoutQuery(
                query: seeded("\(focus) book philosophy", anchors),
                lane: .deepRead,
                providers: [.googleBooks, .openLibrary]
            ),
            DeepScoutQuery(
                query: condensed(focus),
                lane: .teacherLecture,
                providers: [.youtube]
            ),
            DeepScoutQuery(
                query: "\(condensed(focus)) podcast",
                lane: .teacherLecture,
                providers: [.youtube, .podcast]
            )
        ]
    }

    private static func surveyQueries(focus: String, anchors: String) -> [DeepScoutQuery] {
        conceptQueries(focus: focus, anchors: anchors) + [
            DeepScoutQuery(
                query: "\(focus) bibliography recommended books",
                lane: .deepRead,
                providers: [.googleBooks, .openLibrary, .web]
            )
        ]
    }

    /// Condenses a long question focus into the short keyword query a person
    /// would actually type into YouTube ("peak human mental physical state"
    /// instead of the full sentence). Long queries surface loose, off-topic hits.
    static func condensed(_ focus: String, limit: Int = 5) -> String {
        let stopwords: Set<String> = [
            "the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "how",
            "can", "it", "be", "is", "are", "was", "were", "what", "why", "when",
            "where", "which", "do", "does", "did", "with", "that", "this", "its",
            "my", "your", "our", "their", "about", "into", "from", "at", "by"
        ]
        let words = focus.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 && !stopwords.contains($0) }
        guard !words.isEmpty else { return focus }
        return words.prefix(limit).joined(separator: " ")
    }

    private static func normalizedFocus(for profile: InquiryBranchResearchProfile) -> String {
        let raw = (profile.sourceQuery ?? profile.activeQuestionTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        let stripped = lower
            .replacingOccurrences(of: #"^(what|who|where|when|why|how)\s+(is|are|was|were|does|do|did|can|could|should|would)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(what|who|where|when|why|how)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\?\.!]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return stripped.isEmpty ? "this question" : stripped
    }

    private static func deduped(_ queries: [DeepScoutQuery]) -> [DeepScoutQuery] {
        var seen: Set<String> = []
        return queries.compactMap { query in
            let normalized = InquiryPlacementEngine.normalized(query.query)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return query
        }
    }

    private static func containsAny(_ text: String, _ terms: Set<String>) -> Bool {
        terms.contains { text.contains($0) }
    }

    private static let clinicalTerms: Set<String> = [
        "anxiety", "depression", "disorder", "mental health", "clinical", "therapy",
        "treatment", "patient", "trial", "randomized", "meta-analysis", "systematic review",
        "hypertension", "blood pressure", "ptsd", "stress reduction"
    ]

    private static let mechanismTerms: Set<String> = [
        "mechanism", "physiology", "nervous system", "vagus", "vagal", "hrv",
        "heart rate variability", "carbon dioxide", "co2", "chemoreceptor", "autonomic"
    ]

    private static let practiceTerms: Set<String> = [
        "practice", "technique", "protocol", "how to", "exercise", "breathe", "breathing pattern",
        "contraindication", "safety"
    ]

    private static let lineageTerms: Set<String> = [
        "history", "lineage", "origin", "ancient", "tradition", "vedic", "tantra", "hatha"
    ]

    private static let philosophicalTerms: Set<String> = [
        "philosophy", "spiritual", "yoga sutra", "upanishad", "subtle body"
    ]

    private static let surveyTerms: Set<String> = [
        "best sources", "recommended sources", "reading list", "bibliography", "where should i start"
    ]
}
