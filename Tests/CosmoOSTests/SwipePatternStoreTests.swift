import XCTest
@testable import CosmoOS

/// Deterministic coverage for the pattern layer: candidate matching, weaver
/// response parsing/validation, membership application, and the derived
/// signature card for legacy analyses.
@MainActor
final class SwipePatternStoreTests: XCTestCase {

    private func makePattern(
        name: String = "Receipts-first myth bust",
        beats: [String] = ["MythStatement", "DataReceipt", "Reframe"],
        memberUUIDs: [String] = ["a", "b"]
    ) -> SwipePattern {
        SwipePattern(
            name: name,
            definition: "Debunks with third-party data before any opinion.",
            level: .structure,
            beatSignature: beats,
            members: memberUUIDs.map { SwipePatternMember(swipeUUID: $0, evidence: "e-\($0)") }
        )
    }

    // MARK: - Candidate matching (Stage A)

    func testCandidatePatternsMatchOnBeatOverlap() {
        let store = SwipePatternStore.shared
        let pattern = makePattern()
        store.apply(assignments: [], refinements: [], newPatterns: [pattern], wovenUUIDs: [])
        defer {
            store.removeSwipe("a")
            store.removeSwipe("b")
        }

        let strong = store.candidatePatterns(forBeats: ["MythStatement", "DataReceipt", "Reframe"])
        XCTAssertTrue(strong.contains(where: { $0.id == pattern.id }))

        let weak = store.candidatePatterns(forBeats: ["Hook", "CTA"])
        XCTAssertFalse(weak.contains(where: { $0.id == pattern.id }))
    }

    // MARK: - Membership lifecycle

    func testRemovingSwipesDissolvesPatternsBelowTwoMembers() {
        let store = SwipePatternStore.shared
        let pattern = makePattern(name: "Dissolve me", memberUUIDs: ["x1", "x2"])
        store.apply(assignments: [], refinements: [], newPatterns: [pattern], wovenUUIDs: [])

        XCTAssertFalse(store.patterns(containing: "x1").isEmpty)
        store.removeSwipe("x1")
        // One member left — the pattern is no longer a pattern.
        XCTAssertTrue(store.patterns(containing: "x2").isEmpty)
        XCTAssertNil(store.pattern(id: pattern.id))
    }

    func testApplyAssignmentReinforcesExistingPattern() {
        let store = SwipePatternStore.shared
        let pattern = makePattern(name: "Reinforce me", memberUUIDs: ["r1", "r2"])
        store.apply(assignments: [], refinements: [], newPatterns: [pattern], wovenUUIDs: [])
        defer { ["r1", "r2", "r3"].forEach { store.removeSwipe($0) } }

        store.apply(
            assignments: [(pattern.id, SwipePatternMember(swipeUUID: "r3", evidence: "also receipts-first"))],
            refinements: [(pattern.id, "Sharper name", nil)],
            newPatterns: [],
            wovenUUIDs: ["r3"]
        )

        let updated = store.pattern(id: pattern.id)
        XCTAssertEqual(updated?.members.count, 3)
        XCTAssertEqual(updated?.name, "Sharper name")
        // Duplicate assignment is idempotent.
        store.apply(
            assignments: [(pattern.id, SwipePatternMember(swipeUUID: "r3", evidence: "dupe"))],
            refinements: [], newPatterns: [], wovenUUIDs: ["r3"]
        )
        XCTAssertEqual(store.pattern(id: pattern.id)?.members.count, 3)
    }

    // MARK: - Weaver response parsing + validation

    func testWeaverResponseParsesAndValidatesUUIDs() {
        let store = SwipePatternStore.shared
        let existing = makePattern(name: "Existing", memberUUIDs: ["w1", "w2"])
        store.apply(assignments: [], refinements: [], newPatterns: [existing], wovenUUIDs: [])
        defer { ["w1", "w2", "w3", "w4"].forEach { store.removeSwipe($0) } }

        let json = """
        {
          "assignments": [
            {"swipeUUID": "w3", "patternId": "\(existing.id.uuidString)", "evidence": "matches"},
            {"swipeUUID": "NOT-IN-BATCH", "patternId": "\(existing.id.uuidString)", "evidence": "hallucinated"}
          ],
          "refinements": [],
          "newPatterns": [
            {"name": "Dollar-figure opener", "definition": "Opens with a specific dollar amount in the first five words.",
             "level": "hook", "beatSignature": [],
             "members": [{"swipeUUID": "w3", "evidence": "opens $75K"}, {"swipeUUID": "w4", "evidence": "opens $10K"}],
             "novelty": "not a framework"},
            {"name": "Singleton", "definition": "Only one member — must be dropped.",
             "level": "hook", "beatSignature": [],
             "members": [{"swipeUUID": "w4", "evidence": "solo"}]}
          ]
        }
        """
        let response = SwipePatternWeaver.parseResponse(json)
        XCTAssertNotNil(response)

        let wovenAtoms = ["w3", "w4"].map { uuid -> Atom in
            var atom = Atom.new(type: .research, title: "t")
            atom.uuid = uuid
            return atom
        }
        SwipePatternWeaver.apply(response!, wovenAtoms: wovenAtoms, to: store)

        // Valid assignment landed; hallucinated UUID did not.
        let reinforced = store.pattern(id: existing.id)
        XCTAssertEqual(reinforced?.members.count, 3)
        XCTAssertFalse(reinforced!.members.contains { $0.swipeUUID == "NOT-IN-BATCH" })

        // Two-member new pattern created; singleton dropped.
        XCTAssertFalse(store.patterns(containing: "w4").filter { $0.name == "Dollar-figure opener" }.isEmpty)
        XCTAssertTrue(store.patterns.allSatisfy { $0.name != "Singleton" })
    }

    func testWeaverParseHandlesFencesAndGarbage() {
        XCTAssertNotNil(SwipePatternWeaver.parseResponse("```json\n{\"assignments\": []}\n```"))
        XCTAssertNil(SwipePatternWeaver.parseResponse("I found no patterns."))
    }

    // MARK: - Derived signature card (legacy analyses)

    func testDerivedSignatureCardFromLegacyAnalysis() {
        var analysis = SwipeAnalysis(analysisVersion: 2, isFullyAnalyzed: true)
        analysis.hookMechanism = "Plants a who-did-it question"
        analysis.normalizedBeats = ["Hook", "DataReceipt", "Reframe"]
        analysis.niche = "Real Estate"
        analysis.voiceMarkers = ["no hedging"]

        let card = SwipePatternWeaver.derivedSignatureCard(from: analysis)
        XCTAssertNotNil(card)
        XCTAssertTrue(card!.contains("HOOK: Plants a who-did-it question"))
        XCTAssertTrue(card!.contains("BEATS: Hook → DataReceipt → Reframe"))
        XCTAssertTrue(card!.contains("SUBJECT: Real Estate"))
    }

    func testDerivedSignatureCardRequiresSubstance() {
        XCTAssertNil(SwipePatternWeaver.derivedSignatureCard(from: nil))
        let empty = SwipeAnalysis(analysisVersion: 2, isFullyAnalyzed: true)
        XCTAssertNil(SwipePatternWeaver.derivedSignatureCard(from: empty))
        let notAnalyzed = SwipeAnalysis(analysisVersion: 2, isFullyAnalyzed: false)
        XCTAssertNil(SwipePatternWeaver.derivedSignatureCard(from: notAnalyzed))
    }
}
