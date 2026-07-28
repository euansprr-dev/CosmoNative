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

    /// The Study manuscript's speech-tier gate shares this predicate: the
    /// default placeholder slide (blank text) must never count as a transcript.
    func testSlidesCarryTextIgnoresBlankPlaceholders() {
        XCTAssertFalse(SwipePreviewTranscript.slidesCarryText([]))
        XCTAssertFalse(SwipePreviewTranscript.slidesCarryText([slide(""), slide(" \n ")]))
        XCTAssertTrue(SwipePreviewTranscript.slidesCarryText([slide(""), slide("words")]))
    }

    // MARK: - Study tier (GUARD-TWIN of resolve)

    /// A talking-head reel: the worker banks timestamped speech and clears the
    /// slide list. The Study must read the speech tier — parsing the prose
    /// fallback into slide cards here was the bug that made the manuscript
    /// show slide-by-slide while the preview rail showed the voiceover.
    func testVoiceoverOnlyReelResolvesToSpeechTier() {
        let analysis = SwipeAnalysis(
            transcriptSlides: [],
            transcriptSpeechSegments: [segment("Here's the thing", at: 0), segment("about that", at: 2)]
        )
        guard case .speech(let segments) = SwipeStudyTranscriptTier.resolve(analysis: analysis) else {
            return XCTFail("expected the speech tier for a voiceover-only reel")
        }
        XCTAssertEqual(segments.count, 2)
    }

    /// Some voiceover reels ship a blank placeholder slide instead of an empty
    /// list — same verdict, or the tier flips on a formatting accident.
    func testBlankPlaceholderSlidesStillResolveToSpeechTier() {
        let analysis = SwipeAnalysis(
            transcriptSlides: [slide(""), slide("  \n ", number: 2)],
            transcriptSpeechSegments: [segment("spoken", at: 1)]
        )
        guard case .speech = SwipeStudyTranscriptTier.resolve(analysis: analysis) else {
            return XCTFail("expected the speech tier for placeholder-only slides")
        }
    }

    /// No regression for slider reels and carousels: real slide text wins, and
    /// the speech rides along so slide rows can still seek the video.
    func testSlidesWithTextWinAndCarrySpeechAlong() {
        let analysis = SwipeAnalysis(
            transcriptSlides: [slide("Slide one"), slide("Slide two", number: 2)],
            transcriptSpeechSegments: [segment("narration", at: 0)]
        )
        guard case .slides(let slides, let raw, let speech) =
                SwipeStudyTranscriptTier.resolve(analysis: analysis) else {
            return XCTFail("expected the slides tier")
        }
        XCTAssertEqual(slides.map(\.text), ["Slide one", "Slide two"])
        XCTAssertEqual(raw.map(\.text), ["Slide one", "Slide two"], "raw falls back to cleaned when unset")
        XCTAssertEqual(speech.count, 1, "voiceover-plus-text keeps its segments for tap-to-seek")
    }

    func testRawSlidesArePreservedWhenPresent() {
        let analysis = SwipeAnalysis(
            transcriptSlides: [slide("Cleaned")],
            rawTranscriptSlides: [slide("cleaned  RAW  capture")]
        )
        guard case .slides(_, let raw, _) = SwipeStudyTranscriptTier.resolve(analysis: analysis) else {
            return XCTFail("expected the slides tier")
        }
        XCTAssertEqual(raw.map(\.text), ["cleaned  RAW  capture"])
    }

    /// No regression for YouTube / plain sources and legacy swipes: with
    /// nothing banked in the analysis, the prose transcript is still parsed.
    func testNoBankedWordsFallsBackToProse() {
        XCTAssertEqual(SwipeStudyTranscriptTier.resolve(analysis: nil), .proseFallback)
        XCTAssertEqual(SwipeStudyTranscriptTier.resolve(analysis: SwipeAnalysis()), .proseFallback)
        XCTAssertEqual(
            SwipeStudyTranscriptTier.resolve(
                analysis: SwipeAnalysis(transcriptSlides: [slide("")], transcriptSpeechSegments: [])
            ),
            .proseFallback
        )
    }

    /// The two resolvers must never disagree about the same swipe — a slide
    /// tier here and a speech tier in the rail is exactly the reported bug.
    func testStudyTierAgreesWithPreviewResolution() {
        let cases: [SwipeAnalysis] = [
            SwipeAnalysis(transcriptSlides: [], transcriptSpeechSegments: [segment("spoken", at: 0)]),
            SwipeAnalysis(transcriptSlides: [slide("  ")], transcriptSpeechSegments: [segment("spoken", at: 0)]),
            SwipeAnalysis(transcriptSlides: [slide("text")], transcriptSpeechSegments: [segment("spoken", at: 0)]),
            SwipeAnalysis(transcriptSlides: [slide("text")], transcriptSpeechSegments: [])
        ]
        for analysis in cases {
            let preview = SwipePreviewTranscript.resolve(
                analysis: analysis, richTranscript: "prose", richSegments: nil, body: nil
            )
            let study = SwipeStudyTranscriptTier.resolve(analysis: analysis)
            switch (preview, study) {
            case (.slides, .slides), (.speech, .speech):
                continue
            default:
                XCTFail("rail resolved \(preview) but Study resolved \(study)")
            }
        }
    }
}
