// CosmoOS/Tests/CosmoOSTests/InquiryDebriefEngineTests.swift
// The debrief turn contract: JSON parses tolerantly (fences, null update),
// em dashes never survive, and the offline fallback keeps the user's words.

import XCTest
@testable import CosmoOS

final class InquiryDebriefEngineTests: XCTestCase {

    func testParsesProbeTurn() {
        let turn = InquiryDebriefEngine.parseTurn(raw: #"{"say":"You said slow exhales calm you. How?","wrap":false,"updatedUnderstanding":null}"#)
        XCTAssertEqual(turn?.say, "You said slow exhales calm you. How?")
        XCTAssertEqual(turn?.wrap, false)
        XCTAssertNil(turn?.updatedUnderstanding)
    }

    func testParsesWrapTurnInsideFences() {
        let raw = """
        ```json
        {"say":"That closes it well.","wrap":true,"updatedUnderstanding":"Slow exhales calm me because they lengthen the out-breath."}
        ```
        """
        let turn = InquiryDebriefEngine.parseTurn(raw: raw)
        XCTAssertEqual(turn?.wrap, true)
        XCTAssertEqual(turn?.updatedUnderstanding, "Slow exhales calm me because they lengthen the out-breath.")
    }

    func testEmDashesAreStripped() {
        let turn = InquiryDebriefEngine.parseTurn(raw: #"{"say":"Interesting — tell me more","wrap":false}"#)
        XCTAssertEqual(turn?.say.contains("—"), false)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(InquiryDebriefEngine.parseTurn(raw: "I couldn't produce JSON, sorry."))
        XCTAssertNil(InquiryDebriefEngine.parseTurn(raw: #"{"wrap":true}"#))
    }

    func testEmptyUnderstandingBecomesNil() {
        let turn = InquiryDebriefEngine.parseTurn(raw: #"{"say":"Done.","wrap":true,"updatedUnderstanding":"  "}"#)
        XCTAssertEqual(turn?.wrap, true)
        XCTAssertNil(turn?.updatedUnderstanding)
    }

    func testFallbackUnderstandingJoinsUserAnswers() {
        let history: [(role: String, text: String)] = [
            (role: "cosmo", text: "What do you understand now?"),
            (role: "user", text: "Breath pace steers the nervous system."),
            (role: "cosmo", text: "How?"),
            (role: "user", text: "Long exhales raise vagal tone.")
        ]
        XCTAssertEqual(
            InquiryDebriefEngine.fallbackUnderstanding(history: history),
            "Breath pace steers the nervous system. Long exhales raise vagal tone."
        )
        XCTAssertNil(InquiryDebriefEngine.fallbackUnderstanding(history: [(role: "cosmo", text: "Hello?")]))
    }
}
