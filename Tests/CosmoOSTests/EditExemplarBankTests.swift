import XCTest
@testable import CosmoOS

/// The exemplar bank's bloat and wrong-lesson guards: dedup folds repeats
/// into supportCount, struck tombstones swallow re-learned lessons forever,
/// the scope cap holds, retrieval is threshold-gated, and the inline-edit
/// taste block only surfaces beliefs that cleared the repetition bar.
/// (Embedding-free paths throughout — tests must not depend on the cloud,
/// and the bank is designed to degrade to exact-text/token-overlap anyway.)
@MainActor
final class EditExemplarBankTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
    }

    private func makeEpisode(
        clientUuid: String?,
        verdict: InlineEditEpisode.Verdict = .accepted,
        aiText: String,
        slideRole: String? = "hook"
    ) -> InlineEditEpisode {
        InlineEditEpisode(
            id: UUID().uuidString,
            surfaceId: "content:exemplar-test",
            targetId: "content:exemplar-test:draft",
            clientUuid: clientUuid,
            skillId: "inlineEdit",
            ask: "punch up the hook",
            verdict: verdict.rawValue,
            aiText: aiText,
            originalText: nil,
            slideRole: slideRole,
            anchorBefore: nil,
            anchorAfter: nil,
            outcome: InlineEditEpisode.Outcome.tweak.rawValue,
            settledText: nil,
            magnitude: 0.3,
            userReason: nil,
            createdAt: ISO8601.string(from: Date()),
            settledAt: nil
        )
    }

    private func drainScope(_ clientUuid: String?) async {
        for exemplar in await EditExemplarBank.recent(clientUuid: clientUuid, limit: 200) {
            await EditExemplarBank.strike(id: exemplar.id)
        }
    }

    func testIngestDedupFoldsRepeatsIntoSupport() async {
        let scope = "client-dedup-\(UUID().uuidString)"
        let episode = makeEpisode(
            clientUuid: scope,
            aiText: "Here's the thing — most people never start because they overthink."
        )
        await EditExemplarBank.ingest(from: episode, settledText: "Most people never start. They overthink.")
        await EditExemplarBank.ingest(from: episode, settledText: "Most people never start. They overthink.")

        let stored = await EditExemplarBank.recent(clientUuid: scope)
        XCTAssertEqual(stored.count, 1, "An identical pair folds into supportCount, never duplicates")
        XCTAssertEqual(stored.first?.supportCount, 2)
        XCTAssertEqual(stored.first?.slideRole, "hook")
        XCTAssertEqual(stored.first?.kind, EditExemplar.Kind.tweak.rawValue)
    }

    func testStruckExemplarSwallowsRelearnedLesson() async {
        let scope = "client-struck-\(UUID().uuidString)"
        let episode = makeEpisode(
            clientUuid: scope,
            aiText: "A staged sentence the user has permanently vetoed as a lesson."
        )
        await EditExemplarBank.ingest(from: episode, settledText: "The user's own version of that sentence.")
        guard let stored = await EditExemplarBank.recent(clientUuid: scope).first else {
            return XCTFail("Ingest failed")
        }
        await EditExemplarBank.strike(id: stored.id)

        // Re-learning the identical pair must vanish into the tombstone.
        await EditExemplarBank.ingest(from: episode, settledText: "The user's own version of that sentence.")
        let after = await EditExemplarBank.recent(clientUuid: scope)
        XCTAssertTrue(after.isEmpty, "A struck lesson never returns")
    }

    func testRejectedEpisodeIngestsAsRejectPair() async {
        let scope = "client-reject-\(UUID().uuidString)"
        let episode = makeEpisode(
            clientUuid: scope,
            verdict: .rejected,
            aiText: "A third-person restatement the user rejected outright."
        )
        await EditExemplarBank.ingest(from: episode, settledText: "My own first-person version of the idea.")
        let stored = await EditExemplarBank.recent(clientUuid: scope)
        XCTAssertEqual(stored.first?.kind, EditExemplar.Kind.rejectPair.rawValue)
    }

    func testRetrievalIsThresholdGatedAndScoped() async {
        let scope = "client-retrieve-\(UUID().uuidString)"
        let episode = makeEpisode(
            clientUuid: scope,
            aiText: "Open the carousel hook with a bold claim about property investing returns."
        )
        await EditExemplarBank.ingest(from: episode, settledText: "Property returns beat stocks. Here's the math.")

        let matched = await EditExemplarBank.retrieve(
            query: "rewrite the hook about property investing",
            clientUuid: scope
        )
        XCTAssertEqual(matched.count, 1)

        let unmatched = await EditExemplarBank.retrieve(
            query: "schedule my dentist appointment",
            clientUuid: scope
        )
        XCTAssertTrue(unmatched.isEmpty, "No relevant pair → nothing injected, silence over noise")

        let foreign = await EditExemplarBank.retrieve(
            query: "rewrite the hook about property investing",
            clientUuid: "some-other-client-\(UUID().uuidString)"
        )
        XCTAssertTrue(
            foreign.allSatisfy { $0.clientUuid == nil },
            "Another client's scope must never see this client's pairs (personal fallback only)"
        )

        await drainScope(scope)
    }

    func testPromptBlockFramesTheTransformation() async {
        let scope = "client-block-\(UUID().uuidString)"
        let episode = makeEpisode(
            clientUuid: scope,
            aiText: "Here's the thing — consistency really is everything for growth."
        )
        await EditExemplarBank.ingest(from: episode, settledText: "Consistency builds audiences. Nothing else does.")
        let exemplars = await EditExemplarBank.recent(clientUuid: scope)
        guard let block = EditExemplarBank.promptBlock(for: exemplars) else {
            return XCTFail("Expected a prompt block")
        }
        XCTAssertTrue(block.contains("AI VERSION"))
        XCTAssertTrue(block.contains("USER'S VERSION"))
        XCTAssertTrue(block.contains("the transformation is the lesson"))
        XCTAssertNil(EditExemplarBank.promptBlock(for: []), "Empty retrieval renders nothing")

        await drainScope(scope)
    }

    func testScopeCapEvictsLeastSupported() async {
        let scope = "client-cap-\(UUID().uuidString)"
        for index in 0..<(EditExemplarBank.maxActivePerScope + 3) {
            let episode = makeEpisode(
                clientUuid: scope,
                aiText: "Unique staged sentence number \(index) with plenty of distinctive words \(UUID().uuidString)."
            )
            await EditExemplarBank.ingest(
                from: episode,
                settledText: "Unique settled sentence number \(index) reshaped by the user \(UUID().uuidString)."
            )
        }
        let stored = await EditExemplarBank.recent(clientUuid: scope, limit: 200)
        XCTAssertLessThanOrEqual(stored.count, EditExemplarBank.maxActivePerScope,
                                 "The bank is capped — history grows, prompts don't")

        await drainScope(scope)
    }

    // MARK: - Inline-edit taste block

    func testResolveForInlineEditHonorsRepetitionBar() async {
        let scope = "client-taste-\(UUID().uuidString)"
        var profile = TasteProfile(
            id: nil, clientUuid: scope, version: 1,
            beliefsJson: "[]", distilledSignalCount: 0,
            updatedAt: ISO8601.string(from: Date())
        )
        profile.beliefs = [
            TasteBelief(text: "Cut connective openers — start on the claim.", category: "voice", confidence: 0.8, sources: 3),
            TasteBelief(text: "A one-off mood that should not become law yet.", category: "voice", confidence: 0.5, sources: 1),
            TasteBelief(text: "Never use em dashes in drafts.", category: "format", confidence: 1.0, pinned: true, sources: 1),
            TasteBelief(text: "A struck belief that must stay dead.", category: "voice", confidence: 0.9, struck: true, sources: 5)
        ]
        await TasteStore.save(profile)

        let block = await TasteContext.resolveForInlineEdit(clientUuid: scope)
        guard let block else { return XCTFail("Expected a taste block") }
        XCTAssertTrue(block.contains("Cut connective openers"))
        XCTAssertTrue(block.contains("[RULE] Never use em dashes"))
        XCTAssertFalse(block.contains("one-off mood"), "sources < 2 and unpinned stays out — repetition bar")
        XCTAssertFalse(block.contains("struck belief"), "Tombstones never render")
    }
}
