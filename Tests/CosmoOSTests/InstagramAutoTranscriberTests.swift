import XCTest
@testable import CosmoOS

@MainActor
final class InstagramAutoTranscriberTests: XCTestCase {
    func testMergeGeminiBatchResultsKeepsDistinctSlidesSharingHeader() {
        let transcriber = InstagramAutoTranscriber.shared

        let first = TranscriptSlide(
            text: "2016\nWe started a sales business",
            slideNumber: 1,
            timestamp: 0.0,
            endTimestamp: 0.5,
            source: .geminiVision
        )
        let overlapDuplicate = TranscriptSlide(
            text: "2016\nWe started a sales business",
            slideNumber: 1,
            timestamp: 0.25,
            endTimestamp: 0.75,
            source: .geminiVision
        )
        let second = TranscriptSlide(
            text: "2016\nWe launched a training program",
            slideNumber: 2,
            timestamp: 0.8,
            endTimestamp: 1.2,
            source: .geminiVision
        )

        let merged = transcriber.mergeGeminiBatchResults(
            batches: [[first], [overlapDuplicate, second]]
        )

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].text, first.text)
        XCTAssertEqual(merged[1].text, second.text)
    }

    func testParseCleanedSlidesRejectsCountMismatch() {
        let transcriber = InstagramAutoTranscriber.shared
        let response = #"{"slides":[{"index":1,"text":"Only one slide"}]}"#

        XCTAssertNil(transcriber.parseCleanedSlides(from: response, expectedCount: 2))
    }

    func testPostProcessSlidesPreservesCountAndOrder() {
        let transcriber = InstagramAutoTranscriber.shared
        let slides = [
            TranscriptSlide(text: "2016\nWe started something", slideNumber: 1, source: .visionOCR),
            TranscriptSlide(text: "***", slideNumber: 2, source: .visionOCR),
            TranscriptSlide(text: "2017\nWe grew fast", slideNumber: 3, source: .visionOCR)
        ]

        let processed = transcriber.postProcessSlides(slides, contentType: .textOnly)

        XCTAssertEqual(processed.count, 3)
        XCTAssertEqual(processed.map(\.slideNumber), [1, 2, 3])
        XCTAssertEqual(processed[0].text, "2016\nWe started something")
        XCTAssertFalse(processed[1].text.isEmpty)
        XCTAssertEqual(processed[2].text, "2017\nWe grew fast")
    }

    func testOCRToSlidesKeepsBriefSingleFrameSlides() {
        let transcriber = InstagramAutoTranscriber.shared
        let ocrFrames = [
            OCRFrameResult(
                timestamp: 0.0,
                lines: ["First hook"],
                normalizedLineSet: ["first hook"],
                confidence: 0.9
            ),
            OCRFrameResult(
                timestamp: 0.25,
                lines: ["Second slide text"],
                normalizedLineSet: ["second slide text"],
                confidence: 0.9
            )
        ]

        let slides = transcriber.ocrToSlides(ocr: ocrFrames)

        XCTAssertEqual(slides.count, 2)
        XCTAssertEqual(slides[0].text, "First hook")
        XCTAssertEqual(slides[1].text, "Second slide text")
    }

    func testMergeVisualSlidesWithSpeechUsesRealTimestampsForLaterSlides() {
        let transcriber = InstagramAutoTranscriber.shared
        let visualSlides = [
            TranscriptSlide(
                text: "Hook text",
                slideNumber: 1,
                timestamp: 0.0,
                endTimestamp: 1.0,
                source: .geminiVision
            ),
            TranscriptSlide(
                text: "Offer text",
                slideNumber: 2,
                timestamp: 2.0,
                endTimestamp: 3.0,
                source: .geminiVision
            )
        ]
        let speech = [
            SpeechSegment(text: "Details for the second slide.", timestamp: 2.2, duration: 0.6)
        ]

        let merged = transcriber.mergeVisualSlidesWithSpeech(
            visualSlides: visualSlides,
            speech: speech,
            allowSpeechAlignment: true
        )

        XCTAssertEqual(merged.count, 2)
        XCTAssertFalse(merged[0].text.contains("[Voiceover:"))
        XCTAssertTrue(merged[1].text.contains("[Voiceover: Details for the second slide.]"))
    }
}
