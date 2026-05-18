// CosmoOS/AI/DeepScoutRanker.swift

import Foundation

enum DeepScoutRanker {
    static func rank(
        _ candidates: [InquirySourceCandidate],
        profile: InquiryBranchResearchProfile,
        plan: DeepScoutPlan,
        existingSourceRefs: [InquirySourceRef],
        limit: Int = 12
    ) -> [InquirySourceCandidate] {
        let plannedLanes = Set(plan.queries.map(\.lane))
        let scored = candidates.compactMap { candidate -> ScoredCandidate? in
            let text = candidateText(for: candidate)
            guard passesTopicGate(text: text, profile: profile) else { return nil }

            let lane = candidate.sourceLane ?? inferredLane(for: candidate, intent: plan.intent)
            let tokens = InquirySourceRecommendationEngine.significantTokens(text)
            let matchedTokens = Array(tokens.intersection(profile.tokens)).sorted()
            let alreadyImported = alreadyImported(candidate, existingSourceRefs: existingSourceRefs)

            var copy = candidate
            copy.sourceLane = lane
            copy.researchIntent = copy.researchIntent ?? plan.intent
            copy.importStatus = alreadyImported ? .imported : candidate.importStatus

            let score = max(
                0.05,
                min(
                    0.99,
                    baseScore(candidate)
                        + topicBoost(text: text, matchedTokens: matchedTokens, profile: profile)
                        + laneBoost(for: lane, intent: plan.intent)
                        + providerBoost(for: candidate.provider, intent: plan.intent)
                        + roleBoost(for: candidate.evidenceRole, intent: plan.intent)
                        + intentBoost(for: candidate.researchIntent, expected: plan.intent)
                        + (plannedLanes.contains(lane) ? 0.04 : 0)
                        + clinicalDriftPenalty(text: text, lane: lane, intent: plan.intent)
                        + (alreadyImported ? -0.18 : 0)
                )
            )
            copy.score = score
            if copy.reason.isEmpty || copy.reason.hasPrefix("Deep Scout") {
                copy.reason = reason(for: copy, matchedTokens: matchedTokens, intent: plan.intent)
            }
            return ScoredCandidate(candidate: copy, lane: lane, score: score)
        }

        return diversified(scored, limit: limit).map(\.candidate)
    }

    private struct ScoredCandidate {
        var candidate: InquirySourceCandidate
        var lane: InquirySourceLane
        var score: Double
    }

    private static func diversified(_ candidates: [ScoredCandidate], limit: Int) -> [ScoredCandidate] {
        var remaining = candidates.sorted {
            if $0.score == $1.score {
                return $0.candidate.title.localizedCaseInsensitiveCompare($1.candidate.title) == .orderedAscending
            }
            return $0.score > $1.score
        }
        var selected: [ScoredCandidate] = []
        var laneCounts: [InquirySourceLane: Int] = [:]

        while selected.count < limit, !remaining.isEmpty {
            let bestIndex = remaining.indices.max { lhs, rhs in
                adjustedScore(remaining[lhs], laneCounts: laneCounts) < adjustedScore(remaining[rhs], laneCounts: laneCounts)
            } ?? remaining.startIndex
            let next = remaining.remove(at: bestIndex)
            laneCounts[next.lane, default: 0] += 1
            selected.append(next)
        }

        return selected
    }

    private static func adjustedScore(
        _ candidate: ScoredCandidate,
        laneCounts: [InquirySourceLane: Int]
    ) -> Double {
        candidate.score - (Double(laneCounts[candidate.lane, default: 0]) * 0.26)
    }

    private static func baseScore(_ candidate: InquirySourceCandidate) -> Double {
        candidate.score > 0 ? min(candidate.score, 0.55) : 0.35
    }

    private static func topicBoost(
        text: String,
        matchedTokens: [String],
        profile: InquiryBranchResearchProfile
    ) -> Double {
        let overlapBoost = min(0.24, Double(matchedTokens.count) * 0.06)
        let lower = text.lowercased()
        let profileText = [
            profile.deepDiveTitle,
            profile.sourceQuery,
            profile.activeQuestionTitle,
            profile.ancestorTitles.joined(separator: " ")
        ].compactMap { $0 }.joined(separator: " ").lowercased()
        let anchorBoost: Double
        if profileText.contains("pranayama") {
            anchorBoost = containsAny(lower, ["pranayama", "prana"]) ? 0.14 : (containsAny(lower, ["breath", "breathing"]) ? 0.06 : 0)
        } else if profileText.contains("breath") {
            anchorBoost = containsAny(lower, ["breath", "breathing", "respiration", "respiratory"]) ? 0.12 : 0
        } else {
            anchorBoost = 0
        }
        return overlapBoost + anchorBoost
    }

    private static func laneBoost(for lane: InquirySourceLane, intent: InquiryResearchIntent) -> Double {
        switch intent {
        case .conceptExploration:
            switch lane {
            case .primaryText: return 0.24
            case .deepRead: return 0.22
            case .teacherLecture: return 0.19
            case .scholarlyContext: return 0.12
            case .practiceGuide: return 0.08
            case .localLibrary: return 0.10
            case .webResource: return 0.03
            case .clinicalEvidence: return -0.22
            }
        case .philosophicalOrientation, .historicalLineage:
            switch lane {
            case .primaryText: return 0.24
            case .deepRead: return 0.20
            case .scholarlyContext: return 0.17
            case .teacherLecture: return 0.14
            case .practiceGuide: return 0.05
            case .localLibrary: return 0.10
            case .webResource: return 0.04
            case .clinicalEvidence: return -0.18
            }
        case .practiceTechnique:
            switch lane {
            case .practiceGuide: return 0.22
            case .teacherLecture: return 0.18
            case .deepRead, .primaryText: return 0.12
            case .scholarlyContext: return 0.07
            case .clinicalEvidence: return 0.04
            case .localLibrary: return 0.10
            case .webResource: return 0.04
            }
        case .clinicalEvidence:
            return lane == .clinicalEvidence ? 0.24 : (lane == .teacherLecture ? 0.04 : 0.07)
        case .mechanismScience:
            return lane == .scholarlyContext || lane == .clinicalEvidence ? 0.18 : 0.08
        case .sourceSurvey:
            return lane == .webResource ? 0.08 : 0.14
        }
    }

    private static func providerBoost(
        for provider: InquirySourceProvider,
        intent: InquiryResearchIntent
    ) -> Double {
        switch provider {
        case .local: return 0.12
        case .googleBooks, .openLibrary, .internetArchive:
            return nonClinicalIntent(intent) ? 0.12 : 0.04
        case .youtube:
            return nonClinicalIntent(intent) ? 0.10 : 0.03
        case .openAlex, .crossref, .semanticScholar:
            return intent == .clinicalEvidence || intent == .mechanismScience ? 0.11 : 0.05
        case .pubMed:
            return intent == .clinicalEvidence ? 0.12 : -0.07
        case .web:
            return 0.03
        case .arxiv:
            return intent == .mechanismScience ? 0.08 : 0.02
        }
    }

    private static func roleBoost(
        for role: InquiryEvidenceRole,
        intent: InquiryResearchIntent
    ) -> Double {
        if nonClinicalIntent(intent) {
            switch role {
            case .primaryText: return 0.12
            case .book, .lecture, .philosophicalContext, .traditionGuide: return 0.10
            case .localLibrary: return 0.08
            case .review, .metaAnalysis: return -0.04
            case .mechanism, .foundational, .recent: return 0.04
            case .practicalGuide, .videoExplainer, .webContext: return 0.03
            case .counterevidence: return 0.01
            }
        }

        switch role {
        case .review, .metaAnalysis: return 0.13
        case .mechanism, .foundational, .recent: return 0.08
        case .counterevidence: return 0.06
        case .localLibrary: return 0.08
        case .primaryText, .book, .lecture, .philosophicalContext, .traditionGuide: return 0.03
        case .practicalGuide, .videoExplainer, .webContext: return 0.04
        }
    }

    private static func intentBoost(
        for candidateIntent: InquiryResearchIntent?,
        expected: InquiryResearchIntent
    ) -> Double {
        guard let candidateIntent else { return 0 }
        return candidateIntent == expected ? 0.12 : -0.08
    }

    private static func clinicalDriftPenalty(
        text: String,
        lane: InquirySourceLane,
        intent: InquiryResearchIntent
    ) -> Double {
        guard nonClinicalIntent(intent) else { return 0 }
        let lower = text.lowercased()
        var penalty = 0.0
        if lane == .clinicalEvidence { penalty -= 0.18 }
        if containsAny(lower, ["mental disorder", "mental disorders", "mental health", "anxiety", "depression", "stress reduction", "treatment", "patient"]) {
            penalty -= 0.20
        }
        if containsAny(lower, ["systematic review", "meta-analysis", "randomized", "clinical trial"]) {
            penalty -= 0.12
        }
        return max(-0.38, penalty)
    }

    private static func inferredLane(
        for candidate: InquirySourceCandidate,
        intent: InquiryResearchIntent
    ) -> InquirySourceLane {
        switch candidate.provider {
        case .local:
            return .localLibrary
        case .googleBooks, .openLibrary, .internetArchive:
            return candidate.evidenceRole == .primaryText ? .primaryText : .deepRead
        case .youtube:
            return .teacherLecture
        case .pubMed:
            return .clinicalEvidence
        case .openAlex, .crossref, .semanticScholar, .arxiv:
            return intent == .clinicalEvidence ? .clinicalEvidence : .scholarlyContext
        case .web:
            return .webResource
        }
    }

    private static func passesTopicGate(text: String, profile: InquiryBranchResearchProfile) -> Bool {
        let candidateTokens = InquirySourceRecommendationEngine.significantTokens(text)
        if !candidateTokens.intersection(profile.tokens).isEmpty { return true }

        let lower = text.lowercased()
        let profileText = [
            profile.deepDiveTitle,
            profile.sourceQuery,
            profile.activeQuestionTitle
        ].compactMap { $0 }.joined(separator: " ").lowercased()

        if profileText.contains("pranayama") {
            return containsAny(lower, ["pranayama", "prana", "breath", "breathing"])
        }
        if profileText.contains("breath") {
            return containsAny(lower, ["breath", "breathing", "respiration", "respiratory"])
        }
        return false
    }

    private static func alreadyImported(_ candidate: InquirySourceCandidate, existingSourceRefs: [InquirySourceRef]) -> Bool {
        if candidate.importStatus == .imported || candidate.importedSourceUUID != nil {
            return true
        }
        guard let candidateURL = candidate.url?.lowercased() else { return false }
        return existingSourceRefs.contains { ref in
            ref.url?.lowercased() == candidateURL || ref.sourceUUID == candidate.importedSourceUUID
        }
    }

    private static func candidateText(for candidate: InquirySourceCandidate) -> String {
        [
            candidate.title,
            candidate.subtitle,
            candidate.abstract,
            candidate.authors.joined(separator: " "),
            candidate.qualitySignals.joined(separator: " ")
        ].compactMap { $0 }.joined(separator: " ")
    }

    private static func reason(
        for candidate: InquirySourceCandidate,
        matchedTokens: [String],
        intent: InquiryResearchIntent
    ) -> String {
        let lane = candidate.sourceLane?.displayName.lowercased() ?? candidate.evidenceRole.displayName.lowercased()
        if matchedTokens.isEmpty {
            return "Deep Scout matched this as a \(lane) source for \(intent.displayName.lowercased()) exploration."
        }
        return "Deep Scout matched \(matchedTokens.prefix(3).joined(separator: ", ")) and placed it in \(lane)."
    }

    private static func nonClinicalIntent(_ intent: InquiryResearchIntent) -> Bool {
        switch intent {
        case .conceptExploration, .philosophicalOrientation, .historicalLineage, .practiceTechnique, .sourceSurvey:
            return true
        case .clinicalEvidence, .mechanismScience:
            return false
        }
    }

    private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }
}
