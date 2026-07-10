// Tests/CosmoOSTests/CommandKAskCortexTests.swift
// Ask Cortex conversation contracts: the @kind scope grammar, the follow-up
// turn cap, and the session equality that drives pane updates.
// (The knowledge-floor gate is structural: run() returns before any LLM code
// path when the best hit is under the floor — covered by the phase machine.)

import XCTest
@testable import CosmoOS

final class CommandKAskCortexTests: XCTestCase {

    // MARK: - Scope grammar

    func testParseScopeExtractsLeadingKindTokens() {
        let parsed = CommandKAskEngine.parseScope("@note how do hooks work")
        XCTAssertEqual(parsed.types, Set([.note, .stickyNote]))
        XCTAssertEqual(parsed.label, "note")
        XCTAssertEqual(parsed.cleaned, "how do hooks work")
    }

    func testParseScopeStacksMultipleKinds() {
        let parsed = CommandKAskEngine.parseScope("@note @idea what did I say about pacing")
        XCTAssertEqual(parsed.types, Set([.note, .stickyNote, .idea]))
        XCTAssertEqual(parsed.label, "note + idea")
        XCTAssertEqual(parsed.cleaned, "what did I say about pacing")
    }

    func testParseScopeLeavesUnscopedQuestionsAlone() {
        let parsed = CommandKAskEngine.parseScope("how do hooks work")
        XCTAssertNil(parsed.types)
        XCTAssertNil(parsed.label)
        XCTAssertEqual(parsed.cleaned, "how do hooks work")
    }

    func testParseScopeIgnoresUnknownKindAndMidSentenceAtMentions() {
        // Unknown scope word: not a filter, stays in the question.
        let unknown = CommandKAskEngine.parseScope("@banana how do hooks work")
        XCTAssertNil(unknown.types)
        XCTAssertEqual(unknown.cleaned, "@banana how do hooks work")
        // @ mid-sentence is content, not scope.
        let mid = CommandKAskEngine.parseScope("what did @sam say about hooks")
        XCTAssertNil(mid.types)
    }

    func testParseScopeConceptMapsToConnections() {
        let parsed = CommandKAskEngine.parseScope("@concepts trust loops")
        XCTAssertEqual(parsed.types, Set([.connection]))
    }

    // MARK: - Turn stacking

    func testFollowUpTurnsAreCappedAtMaxTurns() async {
        // priorTurns beyond the cap are trimmed from the front — the engine
        // keeps the freshest context, never an unbounded transcript.
        let turns = (0..<10).map {
            CommandKAskSession.CompletedTurn(question: "q\($0)", answer: "a\($0)")
        }
        var captured: CommandKAskSession?
        await CommandKAskEngine.run(question: "@banana-scope-miss q-final", priorTurns: turns) { session in
            if captured == nil { captured = session }
        }
        let kept = captured?.priorTurns ?? []
        XCTAssertEqual(kept.count, CommandKAskEngine.maxTurns - 1)
        XCTAssertEqual(kept.first?.question, "q\(10 - (CommandKAskEngine.maxTurns - 1))")
        XCTAssertEqual(kept.last?.question, "q9")
    }

    func testSessionEqualityTracksTurnsAndAnswer() {
        var a = CommandKAskSession(question: "q")
        var b = a
        XCTAssertEqual(a, b)
        b.answer = "different"
        XCTAssertNotEqual(a, b)
        b = a
        b.priorTurns = [.init(question: "old", answer: "text")]
        XCTAssertNotEqual(a, b, "turn changes must invalidate the pane")
        a.priorTurns = b.priorTurns
        XCTAssertEqual(a, b)
    }
}
