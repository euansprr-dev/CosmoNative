import XCTest
@testable import CosmoOS

/// The Atlas router's hard rules, enforced in parse: keys are never invented,
/// moves without their required targets are dropped (not repaired into
/// guesses), at most one creation move survives, and abstaining is a valid
/// answer. Pure tests — no database, no network.
final class InboxAtlasRouterTests: XCTestCase {

    // MARK: - Fixtures

    private func entry(
        key: String,
        kind: InboxAtlasKind,
        uuid: String = UUID().uuidString,
        name: String = "Entry",
        parentUUID: String? = nil,
        parentName: String? = nil
    ) -> InboxAtlasEntry {
        InboxAtlasEntry(
            key: key,
            kind: kind,
            uuid: uuid,
            name: name,
            charter: "Charter for \(name).",
            examples: [],
            parentUUID: parentUUID,
            parentName: parentName
        )
    }

    private var candidates: [InboxDestinationAtlas.ScoredEntry] {
        [
            .init(entry: entry(key: "cluster-C1", kind: .cluster, name: "Hooks", parentUUID: "TS1", parentName: "Content Lab"), similarity: 0.7),
            .init(entry: entry(key: "thinkspace-TS1", kind: .thinkspace, name: "Content Lab"), similarity: 0.6),
            .init(entry: entry(key: "connection-X1", kind: .connection, name: "Habit Loops"), similarity: 0.65),
            .init(entry: entry(key: "deepdive-D1", kind: .deepDive, name: "Discipline"), similarity: 0.6),
            .init(entry: entry(key: "question-Q1", kind: .question, name: "How do systems beat motivation?", parentUUID: "D1-uuid", parentName: "Discipline"), similarity: 0.55),
            .init(entry: entry(key: "client-A", kind: .client, name: "Deshawn"), similarity: 0.4),
            .init(entry: entry(key: "seedling-S1", kind: .seedling, name: "Directed attention"), similarity: 0.6)
        ]
    }

    private func parse(_ raw: String) -> InboxAtlasRouter.Decision? {
        InboxAtlasRouter.parse(raw: raw, candidates: candidates)
    }

    // MARK: - Happy path

    func testParsesValidatedMovesTitleAndCaptureType() {
        let raw = """
        {"title":"Habit formation takes 66 days","captureType":"insight","moves":[
          {"kind":"feedConnection","targetKey":"connection-X1","section":"evidence","newTitle":null,"parentQuestionKey":null,"growth":"Adds evidence.","confidence":0.9},
          {"kind":"attachClient","targetKey":"client-A","section":null,"newTitle":null,"parentQuestionKey":null,"growth":"In niche.","confidence":0.8}
        ]}
        """
        let decision = parse(raw)
        XCTAssertEqual(decision?.title, "Habit formation takes 66 days")
        XCTAssertEqual(decision?.captureType, "insight")
        XCTAssertEqual(decision?.moves.count, 2)
        XCTAssertEqual(decision?.moves.first?.kind, .feedConnection)
        XCTAssertEqual(decision?.moves.first?.section, "evidence")
        XCTAssertEqual(decision?.moves.last?.kind, .attachClient)
        XCTAssertEqual(decision?.moves.last?.targetKey, "client-A")
    }

    func testSpawnQuestionKeepsValidParentQuestionKey() {
        let raw = """
        {"title":"T","captureType":"question","moves":[
          {"kind":"spawnQuestion","targetKey":"deepdive-D1","section":null,"newTitle":"How much of willpower is environment?","parentQuestionKey":"question-Q1","growth":"Branches.","confidence":0.85}
        ]}
        """
        let move = parse(raw)?.moves.first
        XCTAssertEqual(move?.kind, .spawnQuestion)
        XCTAssertEqual(move?.parentQuestionKey, "question-Q1")
        XCTAssertEqual(move?.newTitle, "How much of willpower is environment?")
    }

    func testAbstainParsesAsEmptyMoves() {
        let decision = parse(#"{"title":"Thought","captureType":"note","moves":[]}"#)
        XCTAssertNotNil(decision)
        XCTAssertTrue(decision?.moves.isEmpty ?? false)
    }

    // MARK: - Hard rules

    func testInventedTargetKeyDropsMove() {
        let raw = """
        {"title":"T","captureType":"insight","moves":[
          {"kind":"feedConnection","targetKey":"connection-INVENTED","section":"evidence","newTitle":null,"parentQuestionKey":null,"growth":"","confidence":0.9}
        ]}
        """
        XCTAssertTrue(parse(raw)?.moves.isEmpty ?? false)
    }

    func testWrongKindTargetDropsMove() {
        // feedConnection pointing at a cluster key must not survive.
        let raw = """
        {"title":"T","captureType":"insight","moves":[
          {"kind":"feedConnection","targetKey":"cluster-C1","section":"evidence","newTitle":null,"parentQuestionKey":null,"growth":"","confidence":0.9}
        ]}
        """
        XCTAssertTrue(parse(raw)?.moves.isEmpty ?? false)
    }

    func testInvalidSectionDropsFeedConnection() {
        let raw = """
        {"title":"T","captureType":"insight","moves":[
          {"kind":"feedConnection","targetKey":"connection-X1","section":"vibes","newTitle":null,"parentQuestionKey":null,"growth":"","confidence":0.9}
        ]}
        """
        XCTAssertTrue(parse(raw)?.moves.isEmpty ?? false)
    }

    func testInventedParentQuestionFallsToTopLevel() {
        let raw = """
        {"title":"T","captureType":"question","moves":[
          {"kind":"spawnQuestion","targetKey":"deepdive-D1","section":null,"newTitle":"New question","parentQuestionKey":"question-INVENTED","growth":"","confidence":0.8}
        ]}
        """
        let move = parse(raw)?.moves.first
        XCTAssertEqual(move?.kind, .spawnQuestion)
        XCTAssertNil(move?.parentQuestionKey)
    }

    func testNonQuestionParentKeyIsRejected() {
        let raw = """
        {"title":"T","captureType":"question","moves":[
          {"kind":"spawnQuestion","targetKey":"deepdive-D1","section":null,"newTitle":"New question","parentQuestionKey":"cluster-C1","growth":"","confidence":0.8}
        ]}
        """
        XCTAssertNil(parse(raw)?.moves.first?.parentQuestionKey)
    }

    func testSecondCreationMoveIsDropped() {
        let raw = """
        {"title":"T","captureType":"idea","moves":[
          {"kind":"spawnQuestion","targetKey":"deepdive-D1","section":null,"newTitle":"Q","parentQuestionKey":null,"growth":"","confidence":0.8},
          {"kind":"startSeedling","targetKey":null,"section":null,"newTitle":"Concept","parentQuestionKey":null,"growth":"","confidence":0.7}
        ]}
        """
        let moves = parse(raw)?.moves ?? []
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves.first?.kind, .spawnQuestion)
    }

    func testFeedSeedlingValidatesTargetKind() {
        // A seedling key parses; a cluster key masquerading as one is dropped.
        let good = """
        {"title":"T","captureType":"insight","moves":[
          {"kind":"feedSeedling","targetKey":"seedling-S1","section":null,"newTitle":null,"parentQuestionKey":null,"growth":"Adds mass.","confidence":0.85}
        ]}
        """
        XCTAssertEqual(parse(good)?.moves.first?.kind, .feedSeedling)
        XCTAssertEqual(parse(good)?.moves.first?.targetKey, "seedling-S1")

        let bad = """
        {"title":"T","captureType":"insight","moves":[
          {"kind":"feedSeedling","targetKey":"cluster-C1","section":null,"newTitle":null,"parentQuestionKey":null,"growth":"","confidence":0.85}
        ]}
        """
        XCTAssertTrue(parse(bad)?.moves.isEmpty ?? false)
    }

    func testStartSeedlingRequiresTitleAndCountsAsCreation() {
        let untitled = """
        {"title":"T","captureType":"insight","moves":[
          {"kind":"startSeedling","targetKey":null,"section":null,"newTitle":null,"parentQuestionKey":null,"growth":"","confidence":0.7}
        ]}
        """
        XCTAssertTrue(parse(untitled)?.moves.isEmpty ?? false)

        let double = """
        {"title":"T","captureType":"insight","moves":[
          {"kind":"startSeedling","targetKey":null,"section":null,"newTitle":"A","parentQuestionKey":null,"growth":"","confidence":0.7},
          {"kind":"germinateDeepDive","targetKey":null,"section":null,"newTitle":"B","parentQuestionKey":null,"growth":"","confidence":0.7}
        ]}
        """
        let moves = parse(double)?.moves ?? []
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves.first?.kind, .startSeedling)
    }

    func testLegacyGerminateConnectionKindIsDroppedInParseButDecodesInBundles() throws {
        // The prompt no longer teaches germinateConnection — an emitted one is
        // dropped at parse (unknown MoveKind)…
        let raw = """
        {"title":"T","captureType":"insight","moves":[
          {"kind":"germinateConnection","targetKey":null,"section":null,"newTitle":"Concept","parentQuestionKey":null,"growth":"","confidence":0.7}
        ]}
        """
        XCTAssertTrue(parse(raw)?.moves.isEmpty ?? false)

        // …while rows classified before the Seedbed still decode and execute
        // (InboxActionExecutor routes them to startSeedling).
        let json = """
        {"bundleId":"b1","title":"Old","createdAt":"2026-07-01T00:00:00Z",
         "recommendations":[{"id":"r1","kind":"germinateConnection","confidence":0.7,
         "suggestedAtomType":"connection","destinationPath":"New concept: Concept",
         "rationale":"Legacy row.","atlasMove":{"germinateTitle":"Concept"}}]}
        """
        let bundle = try JSONDecoder().decode(InboxRecommendationBundle.self, from: Data(json.utf8))
        XCTAssertEqual(bundle.primaryRecommendation?.kind, .germinateConnection)
        XCTAssertEqual(bundle.primaryRecommendation?.kind.legacyClassification, .place)
    }

    func testSpawnQuestionWithoutNewTitleIsDropped() {
        let raw = """
        {"title":"T","captureType":"question","moves":[
          {"kind":"spawnQuestion","targetKey":"deepdive-D1","section":null,"newTitle":null,"parentQuestionKey":null,"growth":"","confidence":0.8}
        ]}
        """
        XCTAssertTrue(parse(raw)?.moves.isEmpty ?? false)
    }

    func testGerminateWithoutTitleIsDropped() {
        let raw = """
        {"title":"T","captureType":"idea","moves":[
          {"kind":"germinateDeepDive","targetKey":null,"section":null,"newTitle":null,"parentQuestionKey":null,"growth":"","confidence":0.8}
        ]}
        """
        XCTAssertTrue(parse(raw)?.moves.isEmpty ?? false)
    }

    func testAtMostThreeMovesSurvive() {
        let move = #"{"kind":"attachClient","targetKey":"client-A","section":null,"newTitle":null,"parentQuestionKey":null,"growth":"","confidence":0.8}"#
        let raw = #"{"title":"T","captureType":"idea","moves":[\#(move),\#(move),\#(move),\#(move)]}"#
        XCTAssertEqual(parse(raw)?.moves.count, 3)
    }

    // MARK: - Prompt assembly

    func testPromptGroupsDestinationsAndIncludesCorrections() {
        let corrections = [
            InboxRoutingCorrectionLedger.Example(
                text: "wholesaling hook idea",
                chosenLabel: "Idea for Deshawn",
                rejectedLabel: "Idea for Mara"
            )
        ]
        let prompt = InboxAtlasRouter.buildPrompt(
            text: "a capture about money",
            heuristicTitle: "Money capture",
            candidates: candidates,
            corrections: corrections
        )
        XCTAssertTrue(prompt.contains("CLIENTS"))
        XCTAssertTrue(prompt.contains("OPEN QUESTIONS"))
        XCTAssertTrue(prompt.contains("\"key\":\"connection-X1\""))
        XCTAssertTrue(prompt.contains("PAST USER DECISIONS"))
        XCTAssertTrue(prompt.contains("user rejected: Idea for Mara"))
        XCTAssertTrue(prompt.contains("a capture about money"))
    }

    // MARK: - Recommendation model compatibility

    func testLegacyBundleWithoutAtlasMoveStillDecodes() throws {
        // A pre-July-2026 bundle: no atlasMove field anywhere.
        let json = """
        {"bundleId":"b1","title":"Old capture","createdAt":"2026-06-01T00:00:00Z",
         "recommendations":[{"id":"r1","kind":"placeInThinkspace","confidence":0.7,
         "suggestedAtomType":"note","destinationPath":"Content Lab",
         "rationale":"Fits the space."}]}
        """
        let bundle = try JSONDecoder().decode(InboxRecommendationBundle.self, from: Data(json.utf8))
        XCTAssertEqual(bundle.primaryRecommendation?.kind, .placeInThinkspace)
        XCTAssertNil(bundle.primaryRecommendation?.atlasMove)
    }

    func testAtlasMoveRoundTripsThroughBundleJSON() throws {
        let recommendation = InboxRecommendation(
            kind: .advanceQuestion,
            confidence: 0.8,
            suggestedAtomType: "note",
            destinationPath: "Discipline › How do systems beat motivation?",
            rationale: "Advances an open question.",
            atlasMove: InboxAtlasMove(
                deepDiveUUID: "D1-uuid",
                deepDiveName: "Discipline",
                questionUUID: "Q1-uuid",
                questionTitle: "How do systems beat motivation?"
            )
        )
        let bundle = InboxRecommendationBundle(title: "T", recommendations: [recommendation])
        let encoded = try XCTUnwrap(bundle.encodedJSONString)
        let decoded = try JSONDecoder().decode(InboxRecommendationBundle.self, from: Data(encoded.utf8))
        XCTAssertEqual(decoded.primaryRecommendation?.kind, .advanceQuestion)
        XCTAssertEqual(decoded.primaryRecommendation?.atlasMove?.questionUUID, "Q1-uuid")
        XCTAssertEqual(decoded.primaryRecommendation?.kind.legacyClassification, .place)
    }

    // MARK: - Atlas entry mechanics

    func testFingerprintChangesWithCharter() {
        let a = entry(key: "cluster-C1", kind: .cluster, name: "Hooks")
        let b = InboxAtlasEntry(
            key: a.key, kind: a.kind, uuid: a.uuid, name: a.name,
            charter: "A different charter.", examples: a.examples,
            parentUUID: a.parentUUID, parentName: a.parentName
        )
        XCTAssertNotEqual(a.fingerprint, b.fingerprint)
    }
}

// MARK: - Quick-thought placement (compact card, never a letter page)

extension InboxAtlasRouterTests {

    func testQuickThoughtCapIsSixtyWords() {
        let thirty = Array(repeating: "word", count: 30).joined(separator: " ")
        XCTAssertTrue(InboxActionExecutor.isQuickThought(thirty))

        let sixty = Array(repeating: "word", count: 60).joined(separator: " ")
        XCTAssertTrue(InboxActionExecutor.isQuickThought(sixty))

        let sixtyOne = Array(repeating: "word", count: 61).joined(separator: " ")
        XCTAssertFalse(InboxActionExecutor.isQuickThought(sixtyOne))

        XCTAssertFalse(InboxActionExecutor.isQuickThought("   "))
    }

    func testThoughtCardSizeIsCompactAndClamped() {
        // One-liner: still card-shaped, never a sliver.
        let tiny = InboxActionExecutor.thoughtCardSize(for: "velvet hammer")
        XCTAssertEqual(tiny.width, 280)
        XCTAssertGreaterThanOrEqual(tiny.height, 116)

        // A 60-word thought: taller, but never a tower — and always under
        // the width that graduates a block back to the page rendering.
        let long = InboxActionExecutor.thoughtCardSize(
            for: Array(repeating: "thought", count: 60).joined(separator: " ")
        )
        XCTAssertEqual(long.width, 280)
        XCTAssertLessThanOrEqual(long.height, 340)
        XCTAssertGreaterThan(long.height, tiny.height)
    }
}
