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
