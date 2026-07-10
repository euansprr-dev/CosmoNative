import XCTest
@testable import CosmoOS

/// Taste engine contracts: JSON-tolerant distiller parsing, the pinned/struck
/// merge rules, and the writing-engine policy shape.
final class TasteEngineTests: XCTestCase {

    func testParseBeliefsToleratesFencesAndProse() {
        let response = """
        Here is the updated profile:
        ```json
        [
          {"text": "Open reels with a concrete claim, not a question.", "category": "hooks", "confidence": 0.7, "sources": 4},
          {"text": "Short", "category": "voice", "confidence": 0.5, "sources": 1},
          {"text": "Keep carousels to four slides with one sentence each.", "category": "weird", "confidence": 1.4}
        ]
        ```
        """
        let beliefs = TasteDistiller.parseBeliefs(response)
        XCTAssertNotNil(beliefs)
        // "Short" is under the 8-char floor → dropped.
        XCTAssertEqual(beliefs?.count, 2)
        XCTAssertEqual(beliefs?[0].category, "hooks")
        // Unknown category coerces to voice; confidence clamps to 0.95.
        XCTAssertEqual(beliefs?[1].category, "voice")
        XCTAssertLessThanOrEqual(beliefs?[1].confidence ?? 99, 0.95)
    }

    func testParseBeliefsRejectsGarbage() {
        XCTAssertNil(TasteDistiller.parseBeliefs("I could not produce beliefs."))
        XCTAssertNil(TasteDistiller.parseBeliefs("[not json"))
    }

    func testProfileBeliefsRoundTrip() {
        var profile = TasteProfile(
            id: nil, clientUuid: "c-1", version: 1,
            beliefsJson: "[]", distilledSignalCount: 0,
            updatedAt: ISO8601.string(from: Date())
        )
        let belief = TasteBelief(text: "Lead with the outcome.", category: "structure", confidence: 0.8, pinned: true, sources: 3)
        profile.beliefs = [belief]
        XCTAssertEqual(profile.beliefs.count, 1)
        XCTAssertEqual(profile.beliefs[0].text, "Lead with the outcome.")
        XCTAssertTrue(profile.beliefs[0].pinned)
    }

    // MARK: - Merge contract (the strike tombstone law)

    private func belief(
        _ text: String, pinned: Bool = false, struck: Bool = false, confidence: Double = 0.6
    ) -> TasteBelief {
        TasteBelief(text: text, category: "voice", confidence: confidence, pinned: pinned, struck: struck, sources: 2)
    }

    func testStruckBeliefSurvivesEveryDistillCycle() {
        let struck = belief("Open with a question.", struck: true)
        // Cycle 1: distiller re-derives the exact struck text — must not join actives.
        let cycle1 = TasteDistiller.mergeContract(
            existing: [struck],
            distilled: [belief("Open with a question."), belief("Short sentences win.")]
        )
        XCTAssertFalse(cycle1.contains { !$0.struck && $0.text == "Open with a question." })
        // The tombstone itself is carried forward in the saved profile…
        XCTAssertTrue(cycle1.contains { $0.struck && $0.text == "Open with a question." })
        // Cycle 2: starting from cycle 1's output, the ban still holds.
        let cycle2 = TasteDistiller.mergeContract(
            existing: cycle1,
            distilled: [belief("Open with a question.")]
        )
        XCTAssertFalse(cycle2.contains { !$0.struck && $0.text == "Open with a question." })
        XCTAssertTrue(cycle2.contains { $0.struck && $0.text == "Open with a question." })
    }

    func testPinnedBeliefSurvivesAndDedupesDistilledTwin() {
        let pinned = belief("Lead with the outcome.", pinned: true, confidence: 1.0)
        let merged = TasteDistiller.mergeContract(
            existing: [pinned],
            distilled: [belief("lead with the outcome."), belief("Concrete nouns over abstractions.")]
        )
        // One copy, and it's the user's pinned one.
        XCTAssertEqual(merged.filter { $0.text.lowercased() == "lead with the outcome." }.count, 1)
        XCTAssertTrue(merged.first { $0.text.lowercased() == "lead with the outcome." }?.pinned ?? false)
        XCTAssertTrue(merged.contains { $0.text == "Concrete nouns over abstractions." })
    }

    func testTombstonesLiveOutsideTheActiveCap() {
        let struck = (0..<4).map { belief("Struck rule \($0)", struck: true) }
        let distilled = (0..<25).map { belief("Active rule \($0)") }
        let merged = TasteDistiller.mergeContract(existing: struck, distilled: distilled, maxBeliefs: 18)
        XCTAssertEqual(merged.filter { !$0.struck }.count, 18, "active beliefs capped")
        XCTAssertEqual(merged.filter(\.struck).count, 4, "tombstones never displaced by the cap")
    }

    func testResolvedPolicyCountsAndEnforcement() {
        let pinned = TasteBelief(text: "Never open with a rhetorical question.", category: "hooks", confidence: 1.0, pinned: true, sources: 1)
        _ = pinned
        // Pure shape check on InferredLesson bridging (effective enforcement).
        let hard = InferredLesson(rule: "r", evidence: "e", category: "hooks", confidence: 1.0, enforcement: .hard)
        let advisory = InferredLesson(rule: "r2", evidence: "e", category: "voice", confidence: 0.5, enforcement: .advisory)
        XCTAssertEqual(hard.effectiveEnforcement, .hard)
        XCTAssertEqual(advisory.effectiveEnforcement, .advisory)
        let policy = ResolvedTastePolicy(hardRules: [hard], advisoryRules: [advisory], formattedBlock: "x")
        XCTAssertEqual(policy.totalCount, 2)
    }
}
