import XCTest
@testable import CosmoOS

/// Edit-loop learning: the harvester's similarity bands (typo vs tweak vs
/// rewrite vs unattributable), anchor relocation, slide roles, the episode
/// store, and the store-level lifecycle (accept opens, overlap harvests,
/// reject captures the why, rollback deletes).
@MainActor
final class InlineEditLearningTests: XCTestCase {
    private var retainedSurfaces: [MutableLearningTestSurface] = []

    override func tearDown() {
        for surface in retainedSurfaces {
            CosmoEditableSurfaceRegistry.shared.unregister(surfaceID: surface.surfaceID)
        }
        retainedSurfaces = []
        super.tearDown()
    }

    // MARK: - Harvester bands

    private let carousel = """
    SLIDE 1
    Most investors think location matters most when buying property.

    SLIDE 2
    Here's the thing — the numbers tell a different story entirely.

    SLIDE 3
    DM me the word DEAL and I'll send you the checklist.
    """

    func testVerbatimSurvivalIsUntouched() {
        let outcome = InlineEditHarvester.harvest(.init(
            verdict: .accepted,
            aiText: "Here's the thing — the numbers tell a different story entirely.",
            originalText: nil,
            anchorBefore: "SLIDE 2",
            anchorAfter: "SLIDE 3",
            currentText: carousel
        ))
        XCTAssertEqual(outcome, .untouched)
    }

    func testSmallTweakYieldsPairWithMagnitude() {
        let tweaked = carousel.replacingOccurrences(
            of: "Here's the thing — the numbers tell a different story entirely.",
            with: "The numbers tell a different story."
        )
        let outcome = InlineEditHarvester.harvest(.init(
            verdict: .accepted,
            aiText: "Here's the thing — the numbers tell a different story entirely.",
            originalText: nil,
            anchorBefore: "SLIDE 2",
            anchorAfter: "SLIDE 3",
            currentText: tweaked
        ))
        guard case .tweak(let settled, let magnitude, let punctuationOnly) = outcome else {
            return XCTFail("Expected tweak, got \(outcome)")
        }
        XCTAssertEqual(settled, "The numbers tell a different story.")
        XCTAssertGreaterThan(magnitude, 0.1)
        XCTAssertLessThan(magnitude, 0.65, "A trim of the same sentence is a tweak, not a rewrite")
        XCTAssertFalse(punctuationOnly)
    }

    func testPunctuationOnlyChangeIsStillATweak() {
        // Em-dash surgery: words identical, punctuation reshaped — the user's
        // real taste rule, invisible to token similarity.
        let tweaked = carousel.replacingOccurrences(
            of: "Here's the thing — the numbers tell a different story entirely.",
            with: "Here's the thing. The numbers tell a different story entirely."
        )
        let outcome = InlineEditHarvester.harvest(.init(
            verdict: .accepted,
            aiText: "Here's the thing — the numbers tell a different story entirely.",
            originalText: nil,
            anchorBefore: "SLIDE 2",
            anchorAfter: "SLIDE 3",
            currentText: tweaked
        ))
        guard case .tweak(_, _, let punctuationOnly) = outcome else {
            return XCTFail("Expected tweak, got \(outcome)")
        }
        XCTAssertTrue(punctuationOnly)
    }

    func testFullRewriteIsNotAStyleLesson() {
        let rewritten = carousel.replacingOccurrences(
            of: "Here's the thing — the numbers tell a different story entirely.",
            with: "My grandmother bought her first duplex at sixty with a reverse mortgage."
        )
        let outcome = InlineEditHarvester.harvest(.init(
            verdict: .accepted,
            aiText: "Here's the thing — the numbers tell a different story entirely.",
            originalText: nil,
            anchorBefore: "SLIDE 2",
            anchorAfter: "SLIDE 3",
            currentText: rewritten
        ))
        XCTAssertEqual(outcome, .rewrite)
    }

    func testUnattributableRegionIsDiscarded() {
        let outcome = InlineEditHarvester.harvest(.init(
            verdict: .accepted,
            aiText: "A sentence that appears nowhere in the document at all today.",
            originalText: nil,
            anchorBefore: nil,
            anchorAfter: nil,
            currentText: "Entirely unrelated content.\nNothing matches here whatsoever.\nStill nothing."
        ))
        XCTAssertEqual(outcome, .discarded)
    }

    func testWhitespaceOnlyDriftIsUntouched() {
        let drifted = carousel.replacingOccurrences(
            of: "Here's the thing — the numbers tell a different story entirely.",
            with: "Here's  the   thing — the numbers tell a different story entirely."
        )
        let outcome = InlineEditHarvester.harvest(.init(
            verdict: .accepted,
            aiText: "Here's the thing — the numbers tell a different story entirely.",
            originalText: nil,
            anchorBefore: "SLIDE 2",
            anchorAfter: "SLIDE 3",
            currentText: drifted
        ))
        XCTAssertEqual(outcome, .untouched)
    }

    func testRejectedWithOriginalStandingIsUntouched() {
        let outcome = InlineEditHarvester.harvest(.init(
            verdict: .rejected,
            aiText: "A punchier version the user turned down.",
            originalText: "Most investors think location matters most when buying property.",
            anchorBefore: "SLIDE 1",
            anchorAfter: "SLIDE 2",
            currentText: carousel
        ))
        XCTAssertEqual(outcome, .untouched)
    }

    func testRejectedThenSelfWrittenYieldsPair() {
        let selfWritten = carousel.replacingOccurrences(
            of: "Most investors think location matters most when buying property.",
            with: "Most investors obsess over location. The data says they shouldn't."
        )
        let outcome = InlineEditHarvester.harvest(.init(
            verdict: .rejected,
            aiText: "Most investors believe location matters most — but they're wrong.",
            originalText: "Most investors think location matters most when buying property.",
            anchorBefore: "SLIDE 1",
            anchorAfter: "SLIDE 2",
            currentText: selfWritten
        ))
        guard case .tweak(let settled, _, _) = outcome else {
            return XCTFail("Expected pair, got \(outcome)")
        }
        XCTAssertTrue(settled.contains("The data says they shouldn't"))
    }

    // MARK: - Slide roles

    func testSlideRoleParsing() {
        let hookIndex = carousel.range(of: "Most investors think")!.lowerBound
        let bodyIndex = carousel.range(of: "the numbers tell")!.lowerBound
        let ctaIndex = carousel.range(of: "DM me the word")!.lowerBound
        XCTAssertEqual(InlineEditSlideRole.role(inText: carousel, atLocation: hookIndex), "hook")
        XCTAssertEqual(InlineEditSlideRole.role(inText: carousel, atLocation: bodyIndex), "body")
        XCTAssertEqual(InlineEditSlideRole.role(inText: carousel, atLocation: ctaIndex), "cta")

        let plainNote = "Just a note.\nNo slides anywhere."
        XCTAssertNil(InlineEditSlideRole.role(inText: plainNote, atLocation: plainNote.startIndex))
    }

    // MARK: - Anchors

    func testAnchorExtractionAroundAppliedRegion() {
        let pre = "First line stays.\nOLD TEXT HERE\nLast line stays."
        let range = pre.range(of: "OLD TEXT HERE")!
        var post = pre
        post.replaceSubrange(range, with: "Fresh applied sentence with plenty of words.")
        let anchors = InlineEditAnchorExtractor.anchors(
            around: range,
            preApplyText: pre,
            appliedText: "Fresh applied sentence with plenty of words.",
            in: post
        )
        XCTAssertEqual(anchors.before, "First line stays.")
        XCTAssertEqual(anchors.after, "Last line stays.")
    }

    func testAnchorsUseOffsetMathForRepeatedLines() {
        // The applied text also appears earlier — a naive search would anchor
        // the FIRST occurrence; offset math must pin the second.
        let repeated = "Repeat me exactly once more.\nMiddle divider line.\nTARGET LINE\nTail line."
        let range = repeated.range(of: "TARGET LINE")!
        var post = repeated
        post.replaceSubrange(range, with: "Repeat me exactly once more.")
        let anchors = InlineEditAnchorExtractor.anchors(
            around: range,
            preApplyText: repeated,
            appliedText: "Repeat me exactly once more.",
            in: post
        )
        XCTAssertEqual(anchors.after, "Tail line.")
        XCTAssertEqual(anchors.before, "Repeat me exactly once more.\nMiddle divider line.")
    }

    // MARK: - Episode store

    func testEpisodeStoreLifecycle() async {
        let episode = makeEpisode(id: UUID().uuidString, surfaceId: "note:store-test")
        await InlineEditEpisodeStore.insert(episode)

        var open = await InlineEditEpisodeStore.openEpisodes(surfaceId: "note:store-test")
        XCTAssertTrue(open.contains { $0.id == episode.id })

        await InlineEditEpisodeStore.markSettled(
            id: episode.id, outcome: .tweak, settledText: "Settled text", magnitude: 0.3
        )
        open = await InlineEditEpisodeStore.openEpisodes(surfaceId: "note:store-test")
        XCTAssertFalse(open.contains { $0.id == episode.id })

        let settled = await InlineEditEpisodeStore.episode(id: episode.id)
        XCTAssertEqual(settled?.outcome, "tweak")
        XCTAssertEqual(settled?.magnitude, 0.3)

        let metrics = await InlineEditEpisodeStore.metrics(clientUuid: nil)
        XCTAssertGreaterThanOrEqual(metrics.tweakCount, 1)
        XCTAssertNotNil(metrics.meanTweakMagnitude)

        await InlineEditEpisodeStore.delete(ids: [episode.id])
        let gone = await InlineEditEpisodeStore.episode(id: episode.id)
        XCTAssertNil(gone)
    }

    func testRecentReasonsSurfaceRejectionWhys() async {
        var episode = makeEpisode(id: UUID().uuidString, surfaceId: "note:reasons-test")
        episode.verdict = InlineEditEpisode.Verdict.rejected.rawValue
        episode.skillId = "inlineEdit"
        await InlineEditEpisodeStore.insert(episode)
        await InlineEditEpisodeStore.attachReason(id: episode.id, reason: "keep it first person")

        let reasons = await InlineEditEpisodeStore.recentReasons(skillId: "inlineEdit")
        XCTAssertTrue(reasons.contains { $0.reason == "keep it first person" })

        await InlineEditEpisodeStore.delete(ids: [episode.id])
    }

    // MARK: - Store lifecycle integration

    func testAcceptOpensEpisodeAndOverlapHarvestSettlesIt() async {
        let surface = registerSurface(
            "note:learn-accept",
            text: "Opening line of the note stays.\nThe middle sentence carries the argument today.\nClosing line of the note stays."
        )
        let store = CosmoInlineAssistantStore(agentBridge: .init { _, _, _ in })

        let firstOp = makeOperation(
            targetID: surface.targetID,
            originalText: "The middle sentence carries the argument today.",
            proposedText: "The middle sentence carries the argument with real numbers behind it."
        )
        store.receive(proposal: makeProposal(surfaceID: surface.surfaceID, ask: "strengthen the middle", operations: [firstOp]))
        await store.accept(operationID: firstOp.id)

        let episode = await InlineEditEpisodeStore.episode(id: firstOp.id.uuidString)
        XCTAssertEqual(episode?.outcome, "settling")
        XCTAssertEqual(episode?.verdict, "accepted")
        XCTAssertTrue(surface.text.contains("real numbers behind it"))

        // A second accepted edit touching the SAME region must harvest the
        // first episode BEFORE applying — the attribution firewall.
        let secondOp = makeOperation(
            targetID: surface.targetID,
            originalText: "The middle sentence carries the argument with real numbers behind it.",
            proposedText: "The middle sentence now cites the exact figures directly."
        )
        store.receive(proposal: makeProposal(surfaceID: surface.surfaceID, ask: "cite figures", operations: [secondOp]))
        await store.accept(operationID: secondOp.id)

        let settledFirst = await InlineEditEpisodeStore.episode(id: firstOp.id.uuidString)
        XCTAssertEqual(settledFirst?.outcome, "untouched",
                       "The user never tweaked between the two accepts — positive confirmation, harvested pre-apply")
        let openSecond = await InlineEditEpisodeStore.episode(id: secondOp.id.uuidString)
        XCTAssertEqual(openSecond?.outcome, "settling")

        await cleanupEpisodes([firstOp.id, secondOp.id])
    }

    func testManualTweakAfterAcceptSettlesAsPair() async {
        let surface = registerSurface(
            "note:learn-tweak",
            text: "Header line stays here.\nOriginal middle line to be replaced entirely.\nFooter line stays here."
        )
        let store = CosmoInlineAssistantStore(agentBridge: .init { _, _, _ in })
        let op = makeOperation(
            targetID: surface.targetID,
            originalText: "Original middle line to be replaced entirely.",
            proposedText: "Here's the thing — consistency is what actually builds an audience over time."
        )
        store.receive(proposal: makeProposal(surfaceID: surface.surfaceID, ask: "improve", operations: [op]))
        await store.accept(operationID: op.id)

        // The user trims the AI's opener — the classic 70%→100% pass.
        surface.text = surface.text.replacingOccurrences(
            of: "Here's the thing — consistency is what actually builds an audience over time.",
            with: "Consistency is what builds an audience."
        )
        guard let episode = await InlineEditEpisodeStore.episode(id: op.id.uuidString) else {
            return XCTFail("Episode missing")
        }
        await InlineEditLearningLoop.shared.settle(episode, currentText: surface.text)

        let settled = await InlineEditEpisodeStore.episode(id: op.id.uuidString)
        XCTAssertEqual(settled?.outcome, "tweak")
        XCTAssertEqual(settled?.settledText, "Consistency is what builds an audience.")
        XCTAssertNotNil(settled?.magnitude)

        let signals = await TasteStore.undistilledSignals(clientUuid: nil, limit: 60)
        XCTAssertTrue(
            signals.contains { $0.kind == TasteSignal.Kind.editTweak.rawValue && $0.content.contains("Consistency is what builds an audience.") },
            "The tweak pair must land as an edit_tweak taste signal"
        )
        await cleanupEpisodes([op.id])
    }

    func testRejectThenFollowUpCapturesReason() async {
        let surface = registerSurface(
            "note:learn-reject",
            text: "Intro line for the rejection test.\nThe sentence Cosmo wanted to change stays put.\nOutro line for the rejection test."
        )
        let store = CosmoInlineAssistantStore(agentBridge: .init { _, _, _ in })
        store.activateSessionIfIdle(surfaceID: surface.surfaceID)

        let op = makeOperation(
            targetID: surface.targetID,
            originalText: "The sentence Cosmo wanted to change stays put.",
            proposedText: "A third-person restatement the user does not want at all."
        )
        store.receive(proposal: makeProposal(surfaceID: surface.surfaceID, ask: "rephrase", operations: [op]))
        await store.reject(operationID: op.id)

        store.composerText = "no — keep it in first person, always"
        await store.submit()

        // Reason attachment is async — poll briefly.
        var reason: String?
        for _ in 0..<20 {
            reason = await InlineEditEpisodeStore.episode(id: op.id.uuidString)?.userReason
            if reason != nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(reason, "no — keep it in first person, always")

        await cleanupEpisodes([op.id])
    }

    func testRollbackDeletesEpisodes() async {
        let surface = registerSurface(
            "note:learn-rollback",
            text: "Rollback test opening line.\nRollback target sentence sits in the middle.\nRollback test closing line."
        )
        let store = CosmoInlineAssistantStore(agentBridge: .init { _, _, _ in })
        let op = makeOperation(
            targetID: surface.targetID,
            originalText: "Rollback target sentence sits in the middle.",
            proposedText: "A staged replacement that will be rolled back shortly."
        )
        store.receive(proposal: makeProposal(surfaceID: surface.surfaceID, ask: "replace", operations: [op]))
        await store.accept(operationID: op.id)
        let opened = await InlineEditEpisodeStore.episode(id: op.id.uuidString)
        XCTAssertNotNil(opened)

        guard let anchorMessage = store.paneMessages.first(where: { $0.proposalID != nil }) else {
            return XCTFail("No proposal message to roll back from")
        }
        await store.rollback(fromMessageID: anchorMessage.id)

        var episode: InlineEditEpisode?
        for _ in 0..<20 {
            episode = await InlineEditEpisodeStore.episode(id: op.id.uuidString)
            if episode == nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertNil(episode, "A rollback is not a verdict — its episodes must vanish")
    }

    // MARK: - Helpers

    private func registerSurface(_ surfaceID: String, text: String) -> MutableLearningTestSurface {
        let surface = MutableLearningTestSurface(surfaceID: surfaceID, text: text)
        CosmoEditableSurfaceRegistry.shared.register(surface)
        retainedSurfaces.append(surface)
        return surface
    }

    private func makeOperation(
        targetID: String,
        originalText: String?,
        proposedText: String
    ) -> CosmoAssistantProposalOperation {
        CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: targetID,
            anchorID: nil,
            originalText: originalText,
            proposedText: proposedText,
            sourceHash: "test-hash",
            rationale: "test"
        )
    }

    private func makeProposal(
        surfaceID: String,
        ask: String,
        operations: [CosmoAssistantProposalOperation]
    ) -> CosmoAssistantProposal {
        CosmoAssistantProposal(
            prompt: ask,
            surfaceID: surfaceID,
            title: "Test proposal",
            summary: "Test proposal summary",
            operations: operations
        )
    }

    private func makeEpisode(id: String, surfaceId: String) -> InlineEditEpisode {
        InlineEditEpisode(
            id: id,
            surfaceId: surfaceId,
            targetId: "\(surfaceId):body",
            clientUuid: nil,
            skillId: "inlineEdit",
            ask: "test ask",
            verdict: InlineEditEpisode.Verdict.accepted.rawValue,
            aiText: "Some staged text with enough substance to matter.",
            originalText: nil,
            slideRole: nil,
            anchorBefore: nil,
            anchorAfter: nil,
            outcome: InlineEditEpisode.Outcome.settling.rawValue,
            settledText: nil,
            magnitude: nil,
            userReason: nil,
            createdAt: ISO8601.string(from: Date()),
            settledAt: nil
        )
    }

    private func cleanupEpisodes(_ ids: [UUID]) async {
        await InlineEditEpisodeStore.delete(ids: ids.map(\.uuidString))
    }
}

/// A registry surface whose text actually mutates on apply — the episode
/// lifecycle needs a real before/after document.
@MainActor
private final class MutableLearningTestSurface: CosmoEditableSurfaceProvider {
    let surfaceID: String
    var text: String
    var targetID: String { "\(surfaceID):body" }

    init(surfaceID: String, text: String) {
        self.surfaceID = surfaceID
        self.text = text
    }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: targetID,
            kind: .text,
            title: "Learning surface",
            text: text,
            sourceHash: CosmoEditableSurfaceHasher.hash(text),
            anchors: [.init(id: "body", label: "Body", utf16Start: 0, utf16Length: text.utf16.count)]
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        guard let placement = CosmoInlineTextEditResolver.placement(for: operation, in: text) else {
            return CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "No placement")
        }
        text.replaceSubrange(placement.range, with: placement.replacementText)
        return CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied")
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected")
    }
}
