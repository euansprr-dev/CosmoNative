// SwipePreviewTranscriptTests.swift
// The preview rail's transcript resolution must mirror the Study's order of
// truth (SwipeStudyModel.loadAtom): cleaned slides → timestamped speech →
// rich-content segments → rich-content prose → body (JSON segments or raw).

import XCTest
@testable import CosmoOS

final class SwipePreviewTranscriptTests: XCTestCase {

    private func slide(_ text: String, number: Int = 1) -> TranscriptSlide {
        TranscriptSlide(text: text, slideNumber: number)
    }

    private func segment(_ text: String, at start: Double) -> TranscriptSegment {
        TranscriptSegment(start: start, end: start + 2, text: text)
    }

    func testSlidesWinWhenAnyHasText() {
        let analysis = SwipeAnalysis(
            transcriptSlides: [slide(""), slide("Hook line", number: 2)],
            transcriptSpeechSegments: [segment("spoken", at: 0)]
        )
        let resolved = SwipePreviewTranscript.resolve(
            analysis: analysis, richTranscript: "prose", richSegments: nil, body: "body"
        )
        guard case .slides(let slides) = resolved else {
            return XCTFail("expected slides, got \(resolved)")
        }
        XCTAssertEqual(slides.count, 2)
    }

    func testBlankSlidesFallThroughToSpeech() {
        let analysis = SwipeAnalysis(
            transcriptSlides: [slide("   "), slide("\n")],
            transcriptSpeechSegments: [segment("spoken", at: 3)]
        )
        let resolved = SwipePreviewTranscript.resolve(
            analysis: analysis, richTranscript: nil, richSegments: nil, body: nil
        )
        guard case .speech(let segments) = resolved else {
            return XCTFail("expected speech, got \(resolved)")
        }
        XCTAssertEqual(segments.first?.text, "spoken")
    }

    func testRichSegmentsBeatRichProse() {
        let resolved = SwipePreviewTranscript.resolve(
            analysis: nil,
            richTranscript: "prose transcript",
            richSegments: [segment("timed", at: 1)],
            body: nil
        )
        guard case .speech(let segments) = resolved else {
            return XCTFail("expected speech, got \(resolved)")
        }
        XCTAssertEqual(segments.first?.text, "timed")
    }

    func testRichProseBeatsBody() {
        let resolved = SwipePreviewTranscript.resolve(
            analysis: nil, richTranscript: "prose transcript", richSegments: nil, body: "raw body"
        )
        XCTAssertEqual(resolved, .prose("prose transcript"))
    }

    func testBodyDecodesJSONSegmentArray() throws {
        let body = String(
            data: try JSONEncoder().encode([segment("from body", at: 12)]),
            encoding: .utf8
        )!
        let resolved = SwipePreviewTranscript.resolve(
            analysis: nil, richTranscript: nil, richSegments: nil, body: body
        )
        guard case .speech(let segments) = resolved else {
            return XCTFail("expected speech, got \(resolved)")
        }
        XCTAssertEqual(segments.first?.text, "from body")
        XCTAssertEqual(segments.first?.start, 12)
    }

    func testRawBodyFallsBackToProse() {
        let resolved = SwipePreviewTranscript.resolve(
            analysis: nil, richTranscript: nil, richSegments: nil, body: "just words"
        )
        XCTAssertEqual(resolved, .prose("just words"))
    }

    func testNothingResolvesEmpty() {
        let resolved = SwipePreviewTranscript.resolve(
            analysis: SwipeAnalysis(), richTranscript: "", richSegments: [], body: nil
        )
        XCTAssertEqual(resolved, .empty)
    }
}
