// CosmoOS/Tests/CosmoOSTests/DeepScoutRankerTests.swift
// Pins the de-yoga'd, domain-generic ranking: anchors derive from the deep dive
// profile (not hardcoded keywords) and clinical content sinks for non-clinical intents.

import XCTest
@testable import CosmoOS

final class DeepScoutRankerTests: XCTestCase {

    private func profile(
        deepDiveTitle: String,
        question: String,
        anchors: Set<String>
    ) -> InquiryBranchResearchProfile {
        InquiryBranchResearchProfile(
            deepDiveTitle: deepDiveTitle,
            activeQuestionTitle: question,
            activeQuestionUUID: "q-1",
            branchNodeId: "node-1",
            ancestorTitles: [],
            claims: [],
            evidence: [],
            anchorTerms: anchors
        )
    }

    private func candidate(
        _ title: String,
        provider: InquirySourceProvider = .web,
        abstract: String? = nil,
        lane: InquirySourceLane? = nil
    ) -> InquirySourceCandidate {
        InquirySourceCandidate(
            provider: provider,
            sourceKind: .web,
            title: title,
            abstract: abstract,
            evidenceRole: .webContext,
            reason: "",
            sourceLane: lane
        )
    }

    private func plan(for profile: InquiryBranchResearchProfile) -> DeepScoutPlan {
        DeepScoutIntentPlanner.plan(for: profile, mode: .deepScout)
    }

    func testNonYogaDomainAnchorsBoostMatchingCandidates() {
        let romanProfile = profile(
            deepDiveTitle: "Roman Concrete",
            question: "Why is Roman concrete so durable?",
            anchors: ["roman", "concrete", "pozzolana", "lime"]
        )
        let ranked = DeepScoutRanker.rank(
            [
                candidate("Pozzolana and lime clasts in ancient marine structures", abstract: "Hot mixing with pozzolana"),
                candidate("Completely unrelated gardening tips", abstract: "tomatoes and basil")
            ],
            profile: romanProfile,
            plan: plan(for: romanProfile),
            existingSourceRefs: []
        )
        XCTAssertEqual(ranked.count, 1)
        XCTAssertTrue(ranked[0].title.contains("Pozzolana"))
    }

    func testTopicGatePassesAnchorOnlyMatches() {
        // Candidate shares no tokens with the question, only with the domain anchors.
        let breathProfile = profile(
            deepDiveTitle: "Breathwork",
            question: "What did ancient cultures believe?",
            anchors: ["breathwork", "pranayama", "spiritus"]
        )
        let ranked = DeepScoutRanker.rank(
            [candidate("Pranayama in classical texts", abstract: "An overview of pranayama")],
            profile: breathProfile,
            plan: plan(for: breathProfile),
            existingSourceRefs: []
        )
        XCTAssertEqual(ranked.count, 1)
    }

    func testClinicalContentSinksForConceptExploration() {
        // "early" not "ancient" — the latter intentionally triggers .historicalLineage.
        let conceptProfile = profile(
            deepDiveTitle: "Breathwork",
            question: "What is the meaning of breath in early cultures?",
            anchors: ["breathwork", "breath"]
        )
        let scoutPlan = plan(for: conceptProfile)
        XCTAssertEqual(scoutPlan.intent, .conceptExploration)

        let ranked = DeepScoutRanker.rank(
            [
                candidate(
                    "Effect of breathwork on mental health: a systematic review",
                    provider: .pubMed,
                    abstract: "Randomized clinical trial for anxiety and depression treatment",
                    lane: .clinicalEvidence
                ),
                candidate(
                    "The breath of life: spirit and breath in ancient traditions",
                    provider: .internetArchive,
                    abstract: "Primary text survey of breath in early cultures",
                    lane: .primaryText
                )
            ],
            profile: conceptProfile,
            plan: scoutPlan,
            existingSourceRefs: []
        )
        XCTAssertEqual(ranked.first?.sourceLane, .primaryText)
        let clinical = ranked.first { $0.sourceLane == .clinicalEvidence }
        if let clinical, let primary = ranked.first(where: { $0.sourceLane == .primaryText }) {
            XCTAssertLessThan(clinical.score, primary.score)
        }
    }

    func testNoHardcodedTopicDependence() {
        // A fully unrelated domain still ranks normally — nothing about the
        // ranker depends on the literal strings "pranayama" or "breath".
        let chessProfile = profile(
            deepDiveTitle: "Chess Endgames",
            question: "How do rook endgames work?",
            anchors: ["chess", "endgame", "rook"]
        )
        let ranked = DeepScoutRanker.rank(
            [candidate("Rook endgame principles", abstract: "Lucena and Philidor positions in chess")],
            profile: chessProfile,
            plan: plan(for: chessProfile),
            existingSourceRefs: []
        )
        XCTAssertEqual(ranked.count, 1)
        XCTAssertGreaterThan(ranked[0].score, 0.3)
    }

    func testJunkCatalogTitlesArePenalized() {
        XCTAssertGreaterThan(
            DeepScoutRanker.junkTitlePenalty(title: "CIA Reading Room cia-rdp85t00875r001600010011-2"), 0.19
        )
        XCTAssertGreaterThan(
            DeepScoutRanker.junkTitlePenalty(title: "CIA Reading Room 00355733: MAJOR DEVELOPMENTS"), 0.19
        )
        XCTAssertEqual(DeepScoutRanker.junkTitlePenalty(title: "Light on Pranayama"), 0)
        XCTAssertEqual(DeepScoutRanker.junkTitlePenalty(title: "CO2 tolerance and breath control in 2024"), 0)
    }

    func testJunkTitleRanksBelowCleanTitle() {
        let breathProfile = profile(
            deepDiveTitle: "Breathwork",
            question: "What is the peak human mental state?",
            anchors: ["breathwork", "peak", "mental"]
        )
        let ranked = DeepScoutRanker.rank(
            [
                candidate("CIA Reading Room cia-rdp85t00875r001600010011-2", provider: .internetArchive, abstract: "peak mental state document", lane: .primaryText),
                candidate("The peak mental state: a reader", provider: .internetArchive, abstract: "An anthology", lane: .primaryText)
            ],
            profile: breathProfile,
            plan: plan(for: breathProfile),
            existingSourceRefs: []
        )
        XCTAssertEqual(ranked.first?.title, "The peak mental state: a reader")
    }

    func testPlanIncludesPodcastQueries() {
        let breathProfile = profile(
            deepDiveTitle: "Breathwork",
            question: "What is the meaning of breath in early cultures?",
            anchors: ["breathwork"]
        )
        let scoutPlan = plan(for: breathProfile)
        XCTAssertTrue(scoutPlan.queries.contains { $0.providers.contains(.podcast) })
    }

    func testPlannerSeedsQueriesWithAnchors() {
        let seeded = profile(
            deepDiveTitle: "Stoicism",
            question: "What is the philosophy of Stoicism?",
            anchors: ["stoicism", "marcus", "aurelius"]
        )
        let scoutPlan = plan(for: seeded)
        let allQueries = scoutPlan.queries.map(\.query).joined(separator: " | ")
        XCTAssertFalse(allQueries.contains("yoga"))
        XCTAssertFalse(allQueries.contains("prana"))
        XCTAssertTrue(allQueries.contains("philosophy"))
    }
}
