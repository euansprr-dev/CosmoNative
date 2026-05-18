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

    func testCaptureIntentClassifierRecognizesQuestionAndSpeculativeClaim() {
        let question = CaptureIntentClassifier.classifyHeuristic(text: "What is pranayama?")
        XCTAssertEqual(question.kind, .question)
        XCTAssertGreaterThanOrEqual(question.confidence, 0.9)

        let speculative = CaptureIntentClassifier.classifyHeuristic(text: "Maybe slow breathing improves HRV")
        XCTAssertEqual(speculative.kind, .speculativeClaim)
        XCTAssertGreaterThanOrEqual(speculative.confidence, 0.75)
    }

    func testConnectionRoutingBuildsBranchCandidateWithVerbatimSections() async {
        let branch = ResearchTreeNode(
            id: "hrv-node",
            kind: .question,
            atomUUID: "question-hrv",
            meta: ResearchTreeNode.Meta(
                label: "How does breathwork affect HRV?",
                nodeType: .branchQuestion,
                relationshipType: .childOf
            )
        )
        let extracts = [
            extract(
                uuid: "claim-1",
                body: "Vagal tone modulates HRV.",
                kind: .claim,
                questionUUID: "question-hrv",
                branchNodeId: "hrv-node",
                sourceUUID: "source-a"
            ),
            extract(
                uuid: "evidence-1",
                body: "A meta-analysis reports slow breathing increases HRV markers.",
                kind: .evidence,
                questionUUID: "question-hrv",
                branchNodeId: "hrv-node",
                sourceUUID: "source-a"
            ),
            extract(
                uuid: "practice-1",
                body: "Practice 4-7-8 breathing before sleep.",
                kind: .practice,
                questionUUID: "question-hrv",
                branchNodeId: "hrv-node",
                sourceUUID: nil
            )
        ]

        let proposals = await ConnectionRoutingEngine().proposals(
            forSession: Atom.new(type: .inquirySession, title: "Breathwork session"),
            branches: [branch],
            extracts: extracts,
            sources: [
                InquirySourceRef(sourceUUID: "source-a", title: "Slow Breathing Meta-analysis")
            ]
        )

        guard let candidate = proposals.first else {
            return XCTFail("Expected one Connection proposal")
        }
        XCTAssertEqual(candidate.branchNodeId, "hrv-node")
        XCTAssertEqual(candidate.proposedTitle, "How does breathwork affect HRV?")
        XCTAssertEqual(candidate.materialCount, 3)
        XCTAssertEqual(candidate.proposedSections[.claims]?.map(\.body), ["Vagal tone modulates HRV."])
        XCTAssertEqual(candidate.proposedSections[.evidence]?.map(\.body), ["A meta-analysis reports slow breathing increases HRV markers."])
        XCTAssertEqual(candidate.proposedSections[.process]?.map(\.body), ["Practice 4-7-8 breathing before sleep."])
        XCTAssertEqual(candidate.proposedSections[.references]?.first?.sourceUUID, "source-a")
    }

    func testInquiryLayoutPayloadRoundTripsFromMenuNotification() {
        let payload = CosmoNotification.Inquiry.LayoutPayload(mode: .write)
        let notification = Notification(
            name: CosmoNotification.Inquiry.layoutRequested,
            object: nil,
            userInfo: payload.userInfo
        )

        let decoded = CosmoNotification.Inquiry.LayoutPayload(from: notification)

        XCTAssertEqual(decoded?.mode, .write)
    }

    func testInquirySourceCandidateDecodesWithoutDeepScoutV2Fields() throws {
        let json = """
        {
          "id": "old-candidate",
          "provider": "openAlex",
          "sourceKind": "review",
          "title": "Systematic review of breathing practices",
          "authors": [],
          "evidenceRole": "review",
          "reason": "Old candidate",
          "score": 0.5,
          "qualitySignals": [],
          "importStatus": "candidate",
          "generatedAt": "2026-05-18T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(InquirySourceCandidate.self, from: json)

        XCTAssertNil(decoded.researchIntent)
        XCTAssertNil(decoded.sourceLane)
        XCTAssertEqual(decoded.provider, .openAlex)
        XCTAssertEqual(decoded.evidenceRole, .review)
    }

    func testInquirySourceLaneDisplayNamesAreHumanReadable() {
        XCTAssertEqual(InquirySourceLane.deepRead.displayName, "Deep read")
        XCTAssertEqual(InquirySourceLane.teacherLecture.displayName, "Lecture")
        XCTAssertEqual(InquirySourceLane.primaryText.displayName, "Primary text")
    }

    func testDeepScoutClassifiesPranayamaDefinitionAsConceptExploration() {
        let intent = DeepScoutIntentPlanner.intent(for: pranayamaProfile())

        XCTAssertEqual(intent, .conceptExploration)
    }

    func testDeepScoutV2QueriesForPranayamaPreferBooksVideosAndTradition() {
        let plan = DeepScoutIntentPlanner.plan(for: pranayamaProfile(), mode: .deepScout)
        let queries = plan.queries.map(\.query).joined(separator: "\n").lowercased()

        XCTAssertEqual(plan.intent, .conceptExploration)
        XCTAssertTrue(queries.contains("pranayama meaning"))
        XCTAssertTrue(queries.contains("prana"))
        XCTAssertTrue(queries.contains("youtube"))
        XCTAssertTrue(queries.contains("book"))
        XCTAssertTrue(queries.contains("patanjali") || queries.contains("hatha yoga pradipika"))
        XCTAssertFalse(queries.contains("randomized controlled trial"))
        XCTAssertFalse(queries.contains("mental disorders"))
    }

    func testDeepScoutV2KeepsClinicalQueriesForClinicalQuestion() {
        let profile = InquiryBranchResearchProfile(
            deepDiveTitle: "Breathwork",
            activeQuestionTitle: "How does pranayama affect anxiety?",
            activeQuestionUUID: "q-clinical",
            branchNodeId: "node-clinical",
            ancestorTitles: [],
            claims: [],
            evidence: []
        )

        let plan = DeepScoutIntentPlanner.plan(for: profile, mode: .deepScout)
        let queries = plan.queries.map(\.query).joined(separator: "\n").lowercased()

        XCTAssertEqual(plan.intent, .clinicalEvidence)
        XCTAssertTrue(queries.contains("systematic review") || queries.contains("meta-analysis"))
        XCTAssertTrue(queries.contains("anxiety"))
    }

    func testDeepScoutParsesOpenLibraryBookCandidate() throws {
        let doc: [String: Any] = [
            "key": "/works/OL123W",
            "title": "Light on Pranayama",
            "author_name": ["B. K. S. Iyengar"],
            "first_publish_year": 1981,
            "first_sentence": ["A practical and philosophical guide to pranayama."],
            "subject": ["Pranayama", "Yoga"]
        ]

        let candidate = try XCTUnwrap(
            DeepScoutProviders.openLibraryCandidate(
                from: doc,
                query: "pranayama book yoga",
                lane: .deepRead,
                intent: .conceptExploration,
                profile: pranayamaProfile()
            )
        )

        XCTAssertEqual(candidate.provider, .openLibrary)
        XCTAssertEqual(candidate.sourceKind, .book)
        XCTAssertEqual(candidate.sourceLane, .deepRead)
        XCTAssertEqual(candidate.researchIntent, .conceptExploration)
        XCTAssertEqual(candidate.evidenceRole, .book)
        XCTAssertEqual(candidate.title, "Light on Pranayama")
        XCTAssertEqual(candidate.authors, ["B. K. S. Iyengar"])
        XCTAssertEqual(candidate.publishedDate, "1981")
        XCTAssertTrue(candidate.url?.contains("openlibrary.org/works/OL123W") == true)
    }

    func testDeepScoutParsesYouTubeCandidateWithLectureLane() throws {
        let item: [String: Any] = [
            "id": ["videoId": "abc123"],
            "snippet": [
                "title": "Pranayama explained by a traditional yoga teacher",
                "description": "A lecture on prana, breath, and the meaning of pranayama.",
                "channelTitle": "Yoga Philosophy Archive",
                "publishedAt": "2020-05-10T12:00:00Z"
            ]
        ]

        let candidate = try XCTUnwrap(
            DeepScoutProviders.youtubeCandidate(
                from: item,
                lane: .teacherLecture,
                intent: .conceptExploration,
                profile: pranayamaProfile()
            )
        )

        XCTAssertEqual(candidate.provider, .youtube)
        XCTAssertEqual(candidate.sourceKind, .video)
        XCTAssertEqual(candidate.sourceLane, .teacherLecture)
        XCTAssertEqual(candidate.researchIntent, .conceptExploration)
        XCTAssertEqual(candidate.evidenceRole, .lecture)
        XCTAssertEqual(candidate.subtitle, "Yoga Philosophy Archive")
        XCTAssertEqual(candidate.publishedDate, "2020")
        XCTAssertEqual(candidate.url, "https://www.youtube.com/watch?v=abc123")
    }

    func testDeepScoutV2PranayamaConceptRanksBookAndLectureAboveClinicalStressPaper() {
        let profile = pranayamaProfile()
        let plan = DeepScoutIntentPlanner.plan(for: profile, mode: .deepScout)
        let book = makeCandidate(
            provider: .googleBooks,
            kind: .book,
            title: "Light on Pranayama",
            abstract: "A deep book on prana, breath, and yogic practice.",
            role: .book,
            lane: .deepRead,
            intent: .conceptExploration
        )
        let lecture = makeCandidate(
            provider: .youtube,
            kind: .video,
            title: "What is pranayama? A traditional yoga lecture",
            abstract: "A teacher explains prana, breath, and the philosophical meaning of pranayama.",
            role: .lecture,
            lane: .teacherLecture,
            intent: .conceptExploration
        )
        let clinical = makeCandidate(
            provider: .openAlex,
            kind: .review,
            title: "Effect of pranayama on stress and mental disorders: a systematic review",
            abstract: "Clinical evidence for anxiety, depression, stress reduction, and mental health treatment.",
            role: .review,
            lane: .clinicalEvidence,
            intent: .clinicalEvidence
        )

        let ranked = DeepScoutRanker.rank([clinical, lecture, book], profile: profile, plan: plan, existingSourceRefs: [], limit: 3)
        let topTwo = ranked.prefix(2).map(\.title)

        XCTAssertTrue(topTwo.contains(book.title))
        XCTAssertTrue(topTwo.contains(lecture.title))
        XCTAssertNotEqual(ranked.first?.title, clinical.title)
    }

    func testDeepScoutV2BalancesConceptResultsAcrossLanes() {
        let profile = pranayamaProfile()
        let plan = DeepScoutIntentPlanner.plan(for: profile, mode: .deepScout)
        let candidates = [
            makeCandidate(provider: .googleBooks, kind: .book, title: "Light on Pranayama", abstract: "A pranayama book.", role: .book, lane: .deepRead),
            makeCandidate(provider: .openLibrary, kind: .book, title: "The Art of Pranayama", abstract: "A pranayama manual.", role: .book, lane: .deepRead),
            makeCandidate(provider: .internetArchive, kind: .book, title: "Pranayama in the Hatha Yoga Pradipika", abstract: "A primary-text commentary.", role: .primaryText, lane: .primaryText),
            makeCandidate(provider: .youtube, kind: .video, title: "Pranayama explained by a teacher", abstract: "A lecture about prana and breath.", role: .lecture, lane: .teacherLecture),
            makeCandidate(provider: .openAlex, kind: .paper, title: "Pranayama and Yoga Philosophy", abstract: "A scholarly context source about pranayama.", role: .philosophicalContext, lane: .scholarlyContext)
        ]

        let ranked = DeepScoutRanker.rank(candidates, profile: profile, plan: plan, existingSourceRefs: [], limit: 4)
        let lanes = Set(ranked.map(\.sourceLane))

        XCTAssertTrue(lanes.contains(.deepRead))
        XCTAssertTrue(lanes.contains(.primaryText))
        XCTAssertTrue(lanes.contains(.teacherLecture))
        XCTAssertTrue(lanes.contains(.scholarlyContext))
    }

    func testDeepScoutScoutQueriesForPranayamaAvoidClinicalDefaults() {
        let queries = InquirySourceRecommendationEngine.scoutQueries(for: pranayamaProfile())
        let joined = queries.joined(separator: "\n").lowercased()

        XCTAssertTrue(joined.contains("book"))
        XCTAssertTrue(joined.contains("youtube"))
        XCTAssertTrue(joined.contains("patanjali") || joined.contains("hatha yoga pradipika"))
        XCTAssertFalse(joined.contains("randomized controlled trial"))
        XCTAssertFalse(joined.contains("mental disorders"))
    }

    func testSourceRecommendationRankCandidatesUsesDeepScoutV2WhenLanesPresent() {
        let profile = pranayamaProfile()
        let book = makeCandidate(
            provider: .googleBooks,
            kind: .book,
            title: "Light on Pranayama",
            abstract: "A deep book on prana, breath, and yogic practice.",
            role: .book,
            lane: .deepRead
        )
        let clinical = makeCandidate(
            provider: .openAlex,
            kind: .review,
            title: "Effectiveness of pranayama for mental disorders: a systematic review",
            abstract: "Clinical outcomes for stress, anxiety, depression, and mental health treatment.",
            role: .review,
            lane: .clinicalEvidence,
            intent: .clinicalEvidence
        )

        let ranked = InquirySourceRecommendationEngine.rankCandidates([clinical, book], profile: profile, existingSourceRefs: [])

        XCTAssertEqual(ranked.first?.title, book.title)
        XCTAssertNotEqual(ranked.first?.sourceLane, .clinicalEvidence)
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

    private func pranayamaProfile() -> InquiryBranchResearchProfile {
        InquiryBranchResearchProfile(
            deepDiveTitle: "Breathwork",
            activeQuestionTitle: "What is pranayama?",
            activeQuestionUUID: "q-prana",
            branchNodeId: "node-prana",
            ancestorTitles: [],
            claims: [],
            evidence: []
        )
    }

    private func makeCandidate(
        provider: InquirySourceProvider,
        kind: InquirySourceKind,
        title: String,
        abstract: String,
        role: InquiryEvidenceRole,
        lane: InquirySourceLane,
        intent: InquiryResearchIntent = .conceptExploration
    ) -> InquirySourceCandidate {
        InquirySourceCandidate(
            provider: provider,
            sourceKind: kind,
            title: title,
            abstract: abstract,
            evidenceRole: role,
            reason: "",
            researchIntent: intent,
            sourceLane: lane
        )
    }

    private func extract(
        uuid: String,
        body: String,
        kind: ExtractKind,
        questionUUID: String,
        branchNodeId: String,
        sourceUUID: String?
    ) -> Atom {
        var atom = Atom.new(type: .extract, title: body, body: body)
        atom.uuid = uuid
        atom = atom.withMetadata(
            ExtractMetadata(
                kind: kind,
                sourceUUID: sourceUUID,
                parentQuestionUUID: questionUUID,
                parentBranchNodeId: branchNodeId
            )
        )
        return atom
    }
}
