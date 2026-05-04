// CosmoOS/Tests/CosmoOSTests/InquiryPlacementEngineTests.swift

import XCTest
@testable import CosmoOS

final class InquiryPlacementEngineTests: XCTestCase {
    func testAxisShiftBecomesRootQuestion() {
        let active = Atom.new(type: .question, title: "What are the most ancient breathwork practices and why were they used?")
        let decision = InquiryPlacementEngine.placement(
            for: "How does breathing affect frequency and biomagnetic field?",
            fullText: "How does breathing affect frequency and biomagnetic field?",
            context: context(activeQuestion: active)
        )

        XCTAssertEqual(decision.nodeType, .rootQuestion)
        XCTAssertEqual(decision.relationshipType, .rootUnderTopic)
        XCTAssertTrue(decision.appearsInBranchMap)
    }

    func testNarrowingFollowupBecomesChildQuestion() {
        let active = Atom.new(type: .question, title: "How does breathing affect frequency and biomagnetic field?")
        let decision = InquiryPlacementEngine.placement(
            for: "What does frequency or biomagnetic energy affect?",
            fullText: "What does frequency or biomagnetic energy affect?",
            context: context(activeQuestion: active)
        )

        XCTAssertEqual(decision.nodeType, .branchQuestion)
        XCTAssertEqual(decision.relationshipType, .consequenceOf)
        XCTAssertTrue(decision.appearsInBranchMap)
    }

    func testEvidencePromptBecomesOperationalAudit() {
        let decision = InquiryPlacementEngine.placement(
            for: "What stronger sources support or challenge this claim?",
            fullText: "What stronger sources support or challenge this claim?",
            context: context()
        )

        XCTAssertEqual(decision.nodeType, .evidenceQualityInvestigation)
        XCTAssertEqual(decision.relationshipType, .evidenceAuditForClaim)
        XCTAssertFalse(decision.appearsInBranchMap)
    }

    func testFindSourcesBecomesSourceSearchTask() {
        let decision = InquiryPlacementEngine.placement(
            for: "Find stronger sources for the biomagnetic field claim",
            fullText: "Find stronger sources for the biomagnetic field claim",
            context: context()
        )

        XCTAssertEqual(decision.nodeType, .sourceSearchTask)
        XCTAssertEqual(decision.relationshipType, .sourceSearchForQuestion)
        XCTAssertFalse(decision.appearsInBranchMap)
    }

    func testSourceQualityWarningDoesNotCreateQuestionNode() {
        let cards = InquiryPlacementEngine.route(
            text: "Breathing may influence biomagnetic field emission.",
            context: context()
        )

        XCTAssertTrue(cards.contains { $0.kind == .sourceQualityWarning })
        XCTAssertTrue(cards.contains { $0.kind == .evidenceAudit && $0.placement?.appearsInBranchMap == false })
        XCTAssertFalse(cards.contains { $0.title == "New branch question" })
    }

    func testDockPrefixParserRoutesExplicitPrefixes() {
        XCTAssertEqual(InquiryDockPrefixParser.parse("claim: breath holds raise CO2").intent, .claim)
        XCTAssertEqual(InquiryDockPrefixParser.parse("counter: this paper contradicts it").intent, .counterevidence)
        XCTAssertEqual(InquiryDockPrefixParser.parse("/sources").intent, .refreshSources)
        XCTAssertEqual(InquiryDockPrefixParser.parse("https://example.com/a").intent, .openSource)
        XCTAssertEqual(InquiryDockPrefixParser.parse("maybe: nasal breathing improves sleep").extractKind, .speculativeClaim)
    }

    func testDockPrefixParserRoutesScoutPrefixToDeepScout() {
        let parsed = InquiryDockPrefixParser.parse("scout: best sources on nasal breathing and HRV")

        XCTAssertEqual(parsed.intent, .deepScout)
        XCTAssertEqual(parsed.body, "best sources on nasal breathing and HRV")
    }

    func testDeepScoutQueryExpansionKeepsBranchAnchorAndAddsSourceAngles() {
        let profile = InquiryBranchResearchProfile(
            deepDiveTitle: "Breathwork",
            activeQuestionTitle: "What is breathwork and how does it affect the body?",
            activeQuestionUUID: "q1",
            branchNodeId: "node-1",
            ancestorTitles: [],
            claims: [],
            evidence: [],
            sourceQuery: "nasal breathing and HRV"
        )

        let queries = InquirySourceRecommendationEngine.scoutQueries(for: profile)

        XCTAssertGreaterThanOrEqual(queries.count, 4)
        XCTAssertTrue(queries.allSatisfy { $0.localizedCaseInsensitiveContains("breath") })
        XCTAssertTrue(queries.contains { $0.localizedCaseInsensitiveContains("review") || $0.localizedCaseInsensitiveContains("meta-analysis") })
        XCTAssertTrue(queries.contains { $0.localizedCaseInsensitiveContains("youtube") || $0.localizedCaseInsensitiveContains("video") })
    }

    func testDeepScoutActivityPlanNamesVisibleSearchSteps() {
        let profile = InquiryBranchResearchProfile(
            deepDiveTitle: "Breathwork",
            activeQuestionTitle: "What is breathwork and how does it affect the body?",
            activeQuestionUUID: "q1",
            branchNodeId: "node-1",
            ancestorTitles: [],
            claims: [],
            evidence: [],
            sourceQuery: "physical benefits"
        )

        let steps = InquirySourceRecommendationEngine.activityPlan(for: profile, mode: .deepScout)

        XCTAssertTrue(steps.first?.localizedCaseInsensitiveContains("Expanding") == true)
        XCTAssertTrue(steps.contains { $0.localizedCaseInsensitiveContains("OpenAlex") })
        XCTAssertTrue(steps.contains { $0.localizedCaseInsensitiveContains("YouTube") })
        XCTAssertTrue(steps.last?.localizedCaseInsensitiveContains("Ranking") == true)
    }

    func testDeepScoutRanksAnchoredYouTubeButRejectsGenericVideo() {
        let profile = InquiryBranchResearchProfile(
            deepDiveTitle: "Breathwork",
            activeQuestionTitle: "What is breathwork and how does it affect the body?",
            activeQuestionUUID: "q1",
            branchNodeId: "node-1",
            ancestorTitles: [],
            claims: [],
            evidence: [],
            sourceQuery: "beginner explanation"
        )
        let genericVideo = InquirySourceCandidate(
            provider: .youtube,
            sourceKind: .video,
            title: "The science of meditation for beginners",
            abstract: "A video about mindfulness, meditation, and focus.",
            evidenceRole: .videoExplainer,
            reason: ""
        )
        let anchoredVideo = InquirySourceCandidate(
            provider: .youtube,
            sourceKind: .video,
            title: "Breathwork explained: how breathing exercises affect the nervous system",
            abstract: "A practical video explaining slow breathing, respiratory physiology, and stress.",
            evidenceRole: .videoExplainer,
            reason: ""
        )

        let ranked = InquirySourceRecommendationEngine.rankCandidates([genericVideo, anchoredVideo], profile: profile, existingSourceRefs: [])

        XCTAssertEqual(ranked.map(\.title), [anchoredVideo.title])
        XCTAssertEqual(ranked.first?.provider, .youtube)
    }

    func testSourceRecommendationRankerPrefersRelevantReview() {
        let profile = InquiryBranchResearchProfile(
            deepDiveTitle: "Breathwork",
            activeQuestionTitle: "How does breathwork affect carbon dioxide tolerance?",
            activeQuestionUUID: "q1",
            branchNodeId: "node-1",
            ancestorTitles: [],
            claims: ["CO2 tolerance may change stress response."],
            evidence: []
        )
        let review = InquirySourceCandidate(
            provider: .openAlex,
            sourceKind: .review,
            title: "Systematic review of breathwork and carbon dioxide tolerance",
            evidenceRole: .review,
            reason: ""
        )
        let weak = InquirySourceCandidate(
            provider: .web,
            sourceKind: .web,
            title: "A generic article about productivity",
            evidenceRole: .webContext,
            reason: ""
        )

        let ranked = InquirySourceRecommendationEngine.rankCandidates([weak, review], profile: profile, existingSourceRefs: [])

        XCTAssertEqual(ranked.first?.title, review.title)
        XCTAssertFalse(ranked.contains { $0.title == weak.title })
        XCTAssertGreaterThan(ranked.first?.score ?? 0, 0.5)
    }

    func testSourceRecommendationRankerRejectsBroadMindfulnessWhenBreathworkIsAnchor() {
        let profile = InquiryBranchResearchProfile(
            deepDiveTitle: "Breathwork",
            activeQuestionTitle: "What is breathwork and how does it affect the body?",
            activeQuestionUUID: "q1",
            branchNodeId: "node-1",
            ancestorTitles: [],
            claims: [],
            evidence: []
        )
        let broadReview = InquirySourceCandidate(
            provider: .openAlex,
            sourceKind: .review,
            title: "Interoception, contemplative practice, and health",
            abstract: "A review of meditation, contemplative practice, and health outcomes.",
            evidenceRole: .review,
            reason: "Academic match for this branch from OpenAlex."
        )
        let breathingPaper = InquirySourceCandidate(
            provider: .crossref,
            sourceKind: .paper,
            title: "Breathwork for optimal breathing",
            abstract: "A paper about breathing exercises and respiratory practice.",
            evidenceRole: .recent,
            reason: "Publisher-indexed source that may answer this branch."
        )

        let ranked = InquirySourceRecommendationEngine.rankCandidates([broadReview, breathingPaper], profile: profile, existingSourceRefs: [])

        XCTAssertEqual(ranked.map(\.title), [breathingPaper.title])
        XCTAssertTrue(ranked.first?.reason.localizedCaseInsensitiveContains("breath") == true)
    }

    func testInquirySessionStructuredDecodesMissingRecommendationFields() throws {
        let original = InquirySessionStructured(researchTree: ResearchTreeDocument.bootstrap(rootQuestionAtomUUID: nil))
        let data = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "recommendationBatches")
        object.removeValue(forKey: "routeReceipts")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(InquirySessionStructured.self, from: legacyData)

        XCTAssertTrue(decoded.recommendationBatches.isEmpty)
        XCTAssertTrue(decoded.routeReceipts.isEmpty)
    }

    @MainActor
    func testWorkspaceDefaultsToSourceRadarWhenSourceTabsExist() {
        let sourceTab = SourceTab(
            id: "source-tab-1",
            kind: .web,
            sourceUUID: "source-uuid-1",
            url: "https://example.com/source",
            title: "Example source",
            attachedQuestionUUID: "question-1",
            attachedNodeId: "node-1"
        )
        var structured = InquirySessionStructured(researchTree: ResearchTreeDocument.bootstrap(rootQuestionAtomUUID: nil))
        structured.sourceTabs = [sourceTab]
        let session = Atom.new(type: .inquirySession, title: "Inquiry")
            .withStructured(structured)
            .withMetadata(InquirySessionMetadata(mainQuestionUUID: "question-1"))

        let viewModel = InquiryWorkspaceViewModel(session: session)

        XCTAssertNil(viewModel.activeSourceTab)

        viewModel.activeSourceTabId = sourceTab.id
        XCTAssertEqual(viewModel.activeSourceTab?.id, sourceTab.id)

        viewModel.closeSourceTab(sourceTab.id)
        XCTAssertNil(viewModel.activeSourceTabId)
        XCTAssertNil(viewModel.activeSourceTab)
    }

    private func context(activeQuestion: Atom? = nil) -> InquiryPlacementEngine.Context {
        InquiryPlacementEngine.Context(
            deepDiveTitle: "Breathwork",
            activeQuestion: activeQuestion,
            activeQuestionUUID: activeQuestion?.uuid,
            activeBranchNodeId: "active-node",
            sourceTabId: nil,
            originExtractUUID: nil,
            originAction: .saveNote,
            questions: activeQuestion.map { [$0] } ?? [],
            claims: []
        )
    }
}
