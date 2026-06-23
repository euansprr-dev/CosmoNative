import XCTest
@testable import CosmoOS

/// The working thread: tool activity accumulates into steps, steps attach to the
/// message that landed them, and persisted sessions replay receipts faithfully.
@MainActor
final class CosmoInlineAssistantActivityTests: XCTestCase {
    private func searchStarted(_ query: String = "curiosity hooks") -> ToolActivityEvent {
        .started(name: "search_swipes", displayLabel: "Searching swipes", args: ["query": query])
    }

    func testToolActivityAccumulatesAndCompletesStepsByName() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)

        store.receiveToolActivity(searchStarted())
        store.receiveToolActivity(.started(name: "get_client_profile", displayLabel: "Checking profile", args: ["clientName": "Hormozi"]))
        store.receiveToolActivity(.completed(name: "search_swipes", displayLabel: "Searching swipes", resultPreview: nil))

        XCTAssertEqual(store.currentRunSteps.count, 2)
        XCTAssertEqual(store.currentRunSteps[0].state, .done)
        XCTAssertNotNil(store.currentRunSteps[0].finishedAt)
        XCTAssertEqual(store.currentRunSteps[0].label, "Pulling swipes on curiosity hooks")
        XCTAssertEqual(store.currentRunSteps[0].subject, "curiosity hooks")
        XCTAssertEqual(store.currentRunSteps[1].state, .running)
    }

    func testCompletionMatchesMostRecentRunningStepWithSameName() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)

        store.receiveToolActivity(searchStarted("first"))
        store.receiveToolActivity(searchStarted("second"))
        store.receiveToolActivity(.completed(name: "search_swipes", displayLabel: "", resultPreview: nil))

        XCTAssertEqual(store.currentRunSteps[0].state, .running)
        XCTAssertEqual(store.currentRunSteps[1].state, .done)
    }

    func testSyntheticPlanningEventsNeverBecomeSteps() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)

        store.receiveToolActivity(.started(name: "inline_context", displayLabel: "Reading note", args: [:]))
        store.receiveToolActivity(.started(name: "inline_thinking", displayLabel: "Thinking", args: [:]))

        XCTAssertTrue(store.currentRunSteps.isEmpty)
        XCTAssertEqual(store.phase, .planning)
    }

    func testAllDoneCompletesStragglers() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)

        store.receiveToolActivity(searchStarted())
        store.receiveToolActivity(.allDone(totalCalls: 1))

        XCTAssertEqual(store.currentRunSteps.first?.state, .done)
        XCTAssertNotNil(store.currentRunSteps.first?.finishedAt)
    }

    func testPaneAnswerAttachesStepsAndClearsRun() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receiveToolActivity(searchStarted())

        store.receivePaneAnswer(title: nil, answer: "Here's the take.", route: .answer)

        let answer = store.paneMessages.last { $0.role == .assistant }
        XCTAssertEqual(answer?.activitySteps?.count, 1)
        XCTAssertEqual(answer?.activitySteps?.first?.state, .done)
        XCTAssertTrue(store.currentRunSteps.isEmpty)
    }

    func testPaneAnswerClearsLiveStatusAfterVisibleOutputLands() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receiveToolActivity(searchStarted())
        store.receiveToolActivity(.completed(name: "search_swipes", displayLabel: "Searching swipes", resultPreview: nil))
        XCTAssertEqual(store.statusText, "Cosmo is writing…")

        store.receivePaneAnswer(title: nil, answer: "Here's the take.", route: .answer)

        XCTAssertNil(store.statusText)
    }

    func testLivePaneAnswerRepairsRawCraftRiffJSON() async {
        let rawRiff = """
        {"bet":"x","beatLabel":"Slide 3 — example/proof beat","targetOriginalText":"Breakdown DSCR loan example","variations":[{"text":"Here's one I actually own. Bought it with a DSCR loan, 15% down. After setup: $15k/mo in rent, $5k/mo clean.","numbers":"$15k/mo revenue; $5k/mo cash flow","borrowedFrom":"Comparable 3, Slide 2","mechanism":"before/after proof"}]}
        """
        let bridge = CosmoInlineAssistantAgentBridge { _, _, store in
            store.receivePaneAnswer(title: nil, answer: rawRiff, route: .answer)
        }
        let store = CosmoInlineAssistantStore(agentBridge: bridge)
        store.composerText = "/Voice Variations give me options for slide 3"

        await store.submit()

        let answer = store.paneMessages.last?.content ?? ""
        XCTAssertTrue(answer.contains("### Slide 3 — example/proof beat — 1 direction"))
        XCTAssertTrue(answer.contains("**1. before/after proof** · from Comparable 3, Slide 2"))
        XCTAssertFalse(answer.contains("\"beatLabel\""))
        XCTAssertFalse(answer.contains("**My bet:** x"))
    }

    func testStreamedAnswerFinalizesWithSteps() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receiveToolActivity(searchStarted())

        store.receivePaneAnswerDelta("Here's ")
        store.receivePaneAnswerDelta("the take.")
        store.receivePaneAnswer(title: nil, answer: "Here's the take.", route: .answer)

        let assistantMessages = store.paneMessages.filter { $0.role == .assistant }
        XCTAssertEqual(assistantMessages.count, 1)
        XCTAssertEqual(assistantMessages.first?.activitySteps?.count, 1)
    }

    func testProposalAttachesStepsAndSecondFinalizeGetsNone() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receiveToolActivity(searchStarted())

        let proposal = CosmoAssistantProposal(
            prompt: "tighten the hook",
            surfaceID: "note:abc",
            title: "What I changed",
            summary: "Tightened the hook.",
            operations: []
        )
        store.receive(proposal: proposal)
        store.receivePaneAnswer(title: nil, answer: "Done — review in place.", route: .action)

        let proposalMessage = store.paneMessages.first { $0.proposalID == proposal.id }
        XCTAssertEqual(proposalMessage?.activitySteps?.count, 1)

        let followUp = store.paneMessages.last { $0.role == .assistant && $0.proposalID == nil }
        XCTAssertNil(followUp?.activitySteps, "Only the first finalize in a run carries the receipt")
    }

    func testUserMessageStampsActiveSkill() async {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.composerText = "/synthesize the through-line"

        await store.submit()

        let userMessage = store.paneMessages.first { $0.role == .user }
        XCTAssertEqual(userMessage?.skillID, CosmoInlineAssistantSkillID.synthesize.rawValue)
    }

    func testLegacyPaneMessageDecodesWithoutNewKeys() throws {
        let legacyJSON = """
        {
          "id": "7E9A2C9E-1111-4222-8333-444455556666",
          "role": "assistant",
          "content": "Older answer.",
          "createdAt": "2026-06-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(CosmoInlineAssistantPaneMessage.self, from: Data(legacyJSON.utf8))

        XCTAssertNil(message.activitySteps)
        XCTAssertNil(message.skillID)
    }

    func testActivityStepsSurvivePersistenceRoundTrip() {
        let persistence = CosmoInlineAssistantSessionPersistence.inMemory()
        let store = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: persistence)
        store.receiveToolActivity(searchStarted())
        store.receivePaneAnswer(title: nil, answer: "Persisted take.", route: .answer)

        let restored = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: persistence)

        let answer = restored.paneMessages.last { $0.role == .assistant }
        XCTAssertEqual(answer?.activitySteps?.count, 1)
        XCTAssertEqual(answer?.activitySteps?.first?.toolName, "search_swipes")
        XCTAssertEqual(answer?.activitySteps?.first?.state, .done)
    }
}

final class CosmoInlineAssistantActivityFormattingTests: XCTestCase {
    private func step(
        tool: String,
        startedAt: Date = Date(timeIntervalSince1970: 0),
        finishedAt: Date? = Date(timeIntervalSince1970: 8)
    ) -> CosmoInlineAssistantActivityStep {
        CosmoInlineAssistantActivityStep(
            toolName: tool,
            label: "Step",
            state: finishedAt == nil ? .running : .done,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }

    func testCurrentCircleOnlySpinsForRunningStepsWhenMotionIsAllowed() {
        let quarterTurnDate = Date(timeIntervalSinceReferenceDate: 0.275)

        XCTAssertEqual(
            CosmoInlineAssistantActivityTimelineMotion.circleRotationDegrees(
                for: .running,
                reduceMotion: false,
                date: quarterTurnDate
            ),
            90,
            accuracy: 0.001
        )
        XCTAssertEqual(
            CosmoInlineAssistantActivityTimelineMotion.circleRotationDegrees(
                for: .done,
                reduceMotion: false,
                date: quarterTurnDate
            ),
            0
        )
        XCTAssertEqual(
            CosmoInlineAssistantActivityTimelineMotion.circleRotationDegrees(
                for: .running,
                reduceMotion: true,
                date: quarterTurnDate
            ),
            0
        )
    }

    func testReceiptSummaryCountsSearchesAndSources() {
        let steps = [
            step(tool: "search_swipes"),
            step(tool: "web_search"),
            step(tool: "read_draft")
        ]
        XCTAssertEqual(
            CosmoInlineAssistantRunReceiptFormatter.summary(steps: steps, sourceCount: 4),
            "Worked for 8s · 2 searches · 4 sources read"
        )
    }

    func testReceiptSummarySingularForms() {
        XCTAssertEqual(
            CosmoInlineAssistantRunReceiptFormatter.summary(steps: [step(tool: "search_ideas")], sourceCount: 1),
            "Worked for 8s · 1 search · 1 source read"
        )
    }

    func testReceiptSummaryFallsBackToStepCount() {
        let steps = [step(tool: "open_atom", startedAt: Date(timeIntervalSince1970: 0), finishedAt: Date(timeIntervalSince1970: 0))]
        XCTAssertEqual(
            CosmoInlineAssistantRunReceiptFormatter.summary(steps: steps, sourceCount: 0),
            "Worked for under a second · 1 step"
        )
    }

    func testDurationLabelMinutes() {
        XCTAssertEqual(CosmoInlineAssistantRunReceiptFormatter.durationLabel(75), "1m 15s")
        XCTAssertEqual(CosmoInlineAssistantRunReceiptFormatter.durationLabel(120), "2m")
    }

    func testTaxonomyBucketsKnownAndHeuristicTools() {
        XCTAssertEqual(CosmoInlineAssistantToolTaxonomy.category(forToolName: "search_swipes"), .search)
        XCTAssertEqual(CosmoInlineAssistantToolTaxonomy.category(forToolName: "web_search"), .web)
        XCTAssertEqual(CosmoInlineAssistantToolTaxonomy.category(forToolName: "get_client_profile"), .profile)
        XCTAssertEqual(CosmoInlineAssistantToolTaxonomy.category(forToolName: "propose_workspace_edit"), .edit)
        XCTAssertEqual(CosmoInlineAssistantToolTaxonomy.category(forToolName: "answer_in_assistant_pane"), .write)
        XCTAssertEqual(CosmoInlineAssistantToolTaxonomy.category(forToolName: "search_memory"), .memory)
        // Heuristic fallbacks for tools the explicit table doesn't name.
        XCTAssertEqual(CosmoInlineAssistantToolTaxonomy.category(forToolName: "search_by_taxonomy_v2"), .search)
        XCTAssertEqual(CosmoInlineAssistantToolTaxonomy.category(forToolName: "get_streak_data"), .read)
        XCTAssertEqual(CosmoInlineAssistantToolTaxonomy.category(forToolName: "send_action_buttons"), .other)
    }

    func testStatusGrammarSubjectPriorityAndTrimming() {
        XCTAssertEqual(
            CosmoInlineAssistantStatusGrammar.subject(args: ["query": " hooks ", "title": "ignored"]),
            "hooks"
        )
        XCTAssertEqual(
            CosmoInlineAssistantStatusGrammar.subject(args: ["client_name": "Hormozi"]),
            "Hormozi"
        )
        XCTAssertNil(CosmoInlineAssistantStatusGrammar.subject(args: ["query": "   "]))
        XCTAssertNil(CosmoInlineAssistantStatusGrammar.subject(args: [:]))
    }
}

final class CosmoInlineAssistantPaneProgressPolicyTests: XCTestCase {
    func testProgressShowsBeforeAnswerIsVisible() {
        XCTAssertTrue(CosmoInlineAssistantPaneProgressPolicy.shouldShow(
            isProcessing: true,
            statusText: "Reading current context",
            hasStreamingAnswer: false,
            hasLiveSteps: false
        ))
        XCTAssertTrue(CosmoInlineAssistantPaneProgressPolicy.shouldShow(
            isProcessing: true,
            statusText: nil,
            hasStreamingAnswer: false,
            hasLiveSteps: true
        ))
    }

    func testProgressHidesOnceAnswerIsVisibleOrSettled() {
        XCTAssertFalse(CosmoInlineAssistantPaneProgressPolicy.shouldShow(
            isProcessing: true,
            statusText: "Cosmo is writing...",
            hasStreamingAnswer: true,
            hasLiveSteps: true
        ))
        XCTAssertFalse(CosmoInlineAssistantPaneProgressPolicy.shouldShow(
            isProcessing: true,
            statusText: nil,
            hasStreamingAnswer: false,
            hasLiveSteps: false
        ))
    }
}

/// Stopping a run: cancellation ends submit, keeps whatever streamed, and
/// settles the receipt instead of vanishing the work.
@MainActor
final class CosmoInlineAssistantCancellationTests: XCTestCase {
    private func slowBridge(streamPartial: Bool) -> CosmoInlineAssistantAgentBridge {
        CosmoInlineAssistantAgentBridge { _, route, store in
            if streamPartial {
                store.receiveToolActivity(.started(
                    name: "search_swipes", displayLabel: "Searching", args: ["query": "hooks"]
                ))
                store.receivePaneAnswerDelta("Partial answer ")
            }
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
    }

    private func waitForProcessing(_ store: CosmoInlineAssistantStore) async {
        for _ in 0..<1_000 where !store.isProcessing {
            await Task.yield()
        }
        XCTAssertTrue(store.isProcessing, "Run never started")
    }

    func testCancelKeepsPartialStreamedAnswerWithReceipt() async {
        let store = CosmoInlineAssistantStore(agentBridge: slowBridge(streamPartial: true))
        store.composerText = "long research question"

        let submitTask = Task { await store.submit() }
        await waitForProcessing(store)

        store.cancelActiveRun()
        await submitTask.value

        XCTAssertFalse(store.isProcessing)
        XCTAssertNil(store.errorText, "Cancellation must not surface as an error")
        let answer = store.paneMessages.last { $0.role == .assistant }
        XCTAssertEqual(answer?.content, "Partial answer ")
        XCTAssertEqual(answer?.activitySteps?.count, 1)
        XCTAssertTrue(store.currentRunSteps.isEmpty)
    }

    func testCancelBeforeAnythingLandedLeavesStoppedMarker() async {
        let store = CosmoInlineAssistantStore(agentBridge: slowBridge(streamPartial: false))
        store.composerText = "long research question"

        let submitTask = Task { await store.submit() }
        await waitForProcessing(store)

        store.cancelActiveRun()
        await submitTask.value

        XCTAssertFalse(store.isProcessing)
        XCTAssertNil(store.errorText)
        XCTAssertEqual(store.paneMessages.last?.role, .system)
        XCTAssertEqual(store.paneMessages.last?.content, "Stopped")
    }

    func testRealErrorsSurfaceAsPaneReplyAndError() async {
        struct FakeError: LocalizedError {
            var errorDescription: String? { "boom" }
        }
        let bridge = CosmoInlineAssistantAgentBridge { _, _, _ in
            throw FakeError()
        }
        let store = CosmoInlineAssistantStore(agentBridge: bridge)
        store.composerText = "question"

        await store.submit()

        XCTAssertEqual(store.errorText, "boom")
        let answer = store.paneMessages.last { $0.role == .assistant }
        XCTAssertEqual(answer?.content, "I hit an error before I could finish: boom")
        XCTAssertTrue(store.isPaneRequested)
    }
}
