// CosmoOS/Tests/CosmoOSTests/PageTranscriptionEngineTests.swift
// Contract tests for the vision-transcription response parser — tolerant of
// code fences and missing optionals, strict about fabrication (no transcript
// key → nil, never invented content). Parity: the fuller suite lives in
// CosmoOS-iOS/CosmoCoreKit/Tests/PageTranscriptionEngineTests.swift.

import XCTest
@testable import CosmoOS

final class PageTranscriptionEngineTests: XCTestCase {

    func testParsesFullContract() throws {
        let raw = """
        {"pageTitle": "Breath notes", "transcript": "- Slow exhales raise vagal tone", "units": [
          {"text": "Slow exhales raise vagal tone", "inkMarks": ["star"]}
        ], "diagrams": [{"description": "Feedback loop", "region": "bottom"}], "confidence": 0.86}
        """
        let parsed = try XCTUnwrap(PageTranscriptionEngine.parse(raw))
        XCTAssertEqual(parsed.pageTitle, "Breath notes")
        XCTAssertEqual(parsed.units.first?.inkMarks, ["star"])
        XCTAssertEqual(parsed.diagrams?.first?.region, "bottom")
        XCTAssertEqual(parsed.confidence, 0.86, accuracy: 0.001)
    }

    func testStripsCodeFences() throws {
        let raw = """
        ```json
        {"transcript": "Meditation before bed", "units": [], "confidence": 1}
        ```
        """
        let parsed = try XCTUnwrap(PageTranscriptionEngine.parse(raw))
        XCTAssertEqual(parsed.transcript, "Meditation before bed")
        // Empty units fall back to one unit wrapping the transcript.
        XCTAssertEqual(parsed.units.count, 1)
    }

    func testConfidenceClampedAndDefaulted() throws {
        XCTAssertEqual(try XCTUnwrap(PageTranscriptionEngine.parse(#"{"transcript": "x", "units": [], "confidence": 7}"#)).confidence, 1.0)
        XCTAssertEqual(try XCTUnwrap(PageTranscriptionEngine.parse(#"{"transcript": "x", "units": []}"#)).confidence, 0.5)
    }

    func testFailureShapes() {
        XCTAssertNil(PageTranscriptionEngine.parse(#"{"units": [], "confidence": 0.9}"#))
        XCTAssertNil(PageTranscriptionEngine.parse("I could not read this page."))
        XCTAssertNil(PageTranscriptionEngine.parse(#"{"transcript": "cut off mid"#))
    }

    func testPromptCarriesSessionVocabulary() {
        let context = PageTranscriptionContext(
            deepDiveTitle: "Breathwork",
            activeQuestionTitle: "How does CO2 tolerance change stress response?",
            lexiconTerms: ["Buteyko"],
            conceptNames: ["Pranayama"],
            inkLegend: "star = key claim"
        )
        let prompt = PageTranscriptionEngine.buildPrompt(context: context)
        XCTAssertTrue(prompt.contains("Breathwork"))
        XCTAssertTrue(prompt.contains("Buteyko"))
        XCTAssertTrue(prompt.contains("star = key claim"))
    }
}
