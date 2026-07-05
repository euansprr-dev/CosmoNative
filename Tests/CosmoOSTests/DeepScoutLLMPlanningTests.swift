import XCTest
@testable import CosmoOS

/// Pure parsing/blending contracts for the LLM-planned Deep Scout pipeline.
final class DeepScoutLLMPlanningTests: XCTestCase {

    // MARK: - Planner parsing

    func testPlannerParsesQueriesAndFillsDefaultProviders() {
        let raw = """
        {"intent":"conceptExploration","queries":[
          {"query":"why we seek hard challenges","lane":"teacherLecture","providers":["youtube","podcast"]},
          {"query":"Alex Hormozi doing hard things","lane":"teacherLecture","providers":["youtube"]},
          {"query":"psychology of pushing limits book","lane":"deepRead","providers":[]}
        ]}
        """
        let plan = DeepScoutLLMPlanner.parse(raw)
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.intent, .conceptExploration)
        XCTAssertEqual(plan?.queries.count, 3)
        // Empty providers fall back to the lane's defaults.
        XCTAssertEqual(plan?.queries[2].providers, [.googleBooks, .openLibrary])
    }

    func testPlannerRejectsTooFewQueries() {
        let raw = """
        {"intent":"conceptExploration","queries":[
          {"query":"one lonely query","lane":"teacherLecture","providers":["youtube"]}
        ]}
        """
        XCTAssertNil(DeepScoutLLMPlanner.parse(raw), "A degenerate plan must fall back to heuristics")
    }

    func testPlannerDedupesEquivalentQueries() {
        let raw = """
        {"intent":"conceptExploration","queries":[
          {"query":"hard challenges podcast","lane":"teacherLecture","providers":["youtube"]},
          {"query":"Hard  Challenges Podcast","lane":"teacherLecture","providers":["podcast"]},
          {"query":"limits book","lane":"deepRead","providers":["googleBooks"]},
          {"query":"voluntary hardship","lane":"teacherLecture","providers":["youtube"]}
        ]}
        """
        let plan = DeepScoutLLMPlanner.parse(raw)
        XCTAssertEqual(plan?.queries.count, 3)
    }

    // MARK: - Judge parsing

    func testJudgeParsingRequiresMajorityCoverage() {
        let candidates = (0..<6).map { makeCandidate(id: "c\($0)", title: "Candidate \($0)") }
        let sparse = #"{"rankings":[{"i":0,"score":90,"reason":"good"},{"i":1,"score":40,"reason":"meh"}]}"#
        XCTAssertTrue(
            DeepScoutLLMRanker.parse(sparse, candidates: candidates).isEmpty,
            "Judging 2 of 6 is a malformed answer — heuristic order must stand"
        )

        let full = #"{"rankings":[{"i":0,"score":90},{"i":1,"score":40},{"i":2,"score":70},{"i":3,"score":10},{"i":4,"score":55},{"i":5,"score":30}]}"#
        let judgments = DeepScoutLLMRanker.parse(full, candidates: candidates)
        XCTAssertEqual(judgments.count, 6)
        XCTAssertEqual(judgments["c0"]?.score ?? 0, 0.9, accuracy: 0.001)
    }

    func testJudgeParsingIgnoresInventedIndexes() {
        let candidates = (0..<4).map { makeCandidate(id: "c\($0)", title: "Candidate \($0)") }
        let raw = #"{"rankings":[{"i":0,"score":80},{"i":1,"score":60},{"i":2,"score":50},{"i":3,"score":40},{"i":9,"score":99}]}"#
        let judgments = DeepScoutLLMRanker.parse(raw, candidates: candidates)
        XCTAssertEqual(judgments.count, 4)
    }

    // MARK: - Blend

    func testBlendDropsJudgedJunkAndBoostsFavorites() {
        let lecture = makeCandidate(id: "lecture", title: "Why We Seek Big Challenges", creator: "Modern Wisdom", score: 0.5)
        let junk = makeCandidate(id: "junk", title: "Marshall Islands climate limits", creator: nil, score: 0.6)
        let judgments: [String: DeepScoutLLMRanker.Judgment] = [
            "lecture": .init(score: 0.9, reason: "Squarely on the question"),
            "junk": .init(score: 0.05, reason: nil)
        ]
        let taste = DeepScoutTasteProfile(
            favoriteCreators: [.init(creator: "Modern Wisdom", provider: "youtube", imports: 5, dismissals: 0)],
            avoidedCreators: []
        )
        let blended = DeepScoutRanker.blend([lecture, junk], judgments: judgments, taste: taste)
        XCTAssertEqual(blended.map(\.id), ["lecture"], "Judged junk must not survive")
        // 0.9*0.7 + 0.5*0.3 = 0.78, +0.08 favorite boost = 0.86
        XCTAssertEqual(blended[0].score, 0.86, accuracy: 0.001)
        XCTAssertEqual(blended[0].reason, "Squarely on the question")
    }

    func testBlendWithoutJudgmentsStillAppliesTaste() {
        let loved = makeCandidate(id: "loved", title: "Interview", creator: "Alex Hormozi", score: 0.5)
        let avoided = makeCandidate(id: "avoided", title: "Motivation edit", creator: "SpamChannel", score: 0.5)
        let taste = DeepScoutTasteProfile(
            favoriteCreators: [.init(creator: "Alex Hormozi", provider: "youtube", imports: 4, dismissals: 0)],
            avoidedCreators: [.init(creator: "SpamChannel", provider: "youtube", imports: 0, dismissals: 3)]
        )
        let blended = DeepScoutRanker.blend([loved, avoided], judgments: [:], taste: taste)
        XCTAssertEqual(blended.first?.id, "loved")
        XCTAssertEqual(blended.first?.score ?? 0, 0.58, accuracy: 0.001)
        XCTAssertEqual(blended.last?.score ?? 0, 0.35, accuracy: 0.001)
    }

    // MARK: - Taste creator identity

    func testCreatorNameUsesChannelForVideosAndAuthorForBooks() {
        let video = makeCandidate(id: "v", title: "Video", creator: "Huberman Lab", score: 0.5)
        XCTAssertEqual(DeepScoutTasteStore.creatorName(for: video), "Huberman Lab")

        var book = InquirySourceCandidate(
            id: "b",
            provider: .googleBooks,
            sourceKind: .book,
            title: "Endure",
            authors: ["Alex Hutchinson"],
            evidenceRole: .book,
            reason: ""
        )
        book.subtitle = "Sports science"
        XCTAssertEqual(DeepScoutTasteStore.creatorName(for: book), "Alex Hutchinson")
    }

    // MARK: - Helpers

    private func makeCandidate(
        id: String,
        title: String,
        creator: String? = nil,
        score: Double = 0.5
    ) -> InquirySourceCandidate {
        InquirySourceCandidate(
            id: id,
            provider: .youtube,
            sourceKind: .video,
            title: title,
            subtitle: creator,
            evidenceRole: .lecture,
            reason: "",
            score: score,
            sourceLane: .teacherLecture
        )
    }
}
