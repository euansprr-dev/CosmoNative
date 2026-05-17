import XCTest
@testable import CosmoOS

@MainActor
final class InstagramAutoTranscriberTests: XCTestCase {
    func testCarouselImageCacheKeyIgnoresExpiringCDNURLWhenShortcodeIsKnown() {
        let firstURL = URL(string: "https://scontent.cdninstagram.com/v/t51.29350-15/slide.jpg?stp=dst-jpg&_nc_cat=1&ccb=1-7")!
        let refreshedURL = URL(string: "https://scontent.cdninstagram.com/v/t51.29350-15/slide.jpg?stp=dst-jpg&_nc_cat=8&ccb=1-7&oh=fresh")!

        let firstKey = InstagramCarouselImageCache.cacheKey(
            shortcode: "ABC123",
            index: 0,
            url: firstURL
        )
        let refreshedKey = InstagramCarouselImageCache.cacheKey(
            shortcode: "ABC123",
            index: 0,
            url: refreshedURL
        )

        XCTAssertEqual(firstKey, refreshedKey)
        XCTAssertEqual(firstKey, "ig-carousel-ABC123-0")
    }

    func testCarouselImageDownloadRequestUsesBrowserHeaders() {
        let url = URL(string: "https://scontent.cdninstagram.com/v/t51.29350-15/slide.jpg?oh=expiring")!

        let request = InstagramCarouselImageCache.request(for: url)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.instagram.com/")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8")
    }

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

    func testDetectTranscriptionContentTypePrefersVoiceoverForCaptionedTalkingHead() {
        let transcriber = InstagramAutoTranscriber.shared
        let visualSlides = [
            TranscriptSlide(text: "Let me break it down", slideNumber: 1, timestamp: 0.0, endTimestamp: 1.0, source: .geminiVision),
            TranscriptSlide(text: "in 60 seconds", slideNumber: 2, timestamp: 1.0, endTimestamp: 2.0, source: .geminiVision),
            TranscriptSlide(text: "this table", slideNumber: 3, timestamp: 2.0, endTimestamp: 3.0, source: .geminiVision),
            TranscriptSlide(text: "your body", slideNumber: 4, timestamp: 3.0, endTimestamp: 4.0, source: .geminiVision)
        ]
        let speech = [
            SpeechSegment(text: "Let me break it down for you in sixty seconds okay this table is your body and every part of it matters.", timestamp: 0.1, duration: 3.8)
        ]

        let contentType = transcriber.detectTranscriptionContentType(
            visualSlides: visualSlides,
            speech: speech,
            duration: 4.0
        )

        XCTAssertEqual(contentType, .voiceoverOnly)
    }

    func testDetectTranscriptionContentTypePreservesTrueTextReel() {
        let transcriber = InstagramAutoTranscriber.shared
        let visualSlides = [
            TranscriptSlide(text: "3 reasons your sales page is underperforming", slideNumber: 1, timestamp: 0.0, endTimestamp: 1.5, source: .visionOCR),
            TranscriptSlide(text: "1. Your hook is vague and makes no promise", slideNumber: 2, timestamp: 1.5, endTimestamp: 3.0, source: .visionOCR),
            TranscriptSlide(text: "2. You explain features before pain or stakes", slideNumber: 3, timestamp: 3.0, endTimestamp: 4.5, source: .visionOCR),
            TranscriptSlide(text: "3. Your CTA asks for too much commitment too early", slideNumber: 4, timestamp: 4.5, endTimestamp: 6.0, source: .visionOCR)
        ]

        let contentType = transcriber.detectTranscriptionContentType(
            visualSlides: visualSlides,
            speech: [],
            duration: 6.0
        )

        XCTAssertEqual(contentType, .textOnly)
    }

    func testDetectTranscriptionContentTypeKeepsVoicePlusDistinctSlides() {
        let transcriber = InstagramAutoTranscriber.shared
        let visualSlides = [
            TranscriptSlide(text: "The old way", slideNumber: 1, timestamp: 0.0, endTimestamp: 1.5, source: .geminiVision),
            TranscriptSlide(text: "Pitch every feature and hope they care", slideNumber: 2, timestamp: 1.5, endTimestamp: 3.0, source: .geminiVision),
            TranscriptSlide(text: "The better way", slideNumber: 3, timestamp: 3.0, endTimestamp: 4.5, source: .geminiVision),
            TranscriptSlide(text: "Lead with the expensive problem and one clear outcome", slideNumber: 4, timestamp: 4.5, endTimestamp: 6.0, source: .geminiVision)
        ]
        let speech = [
            SpeechSegment(text: "Most people pitch every feature and overwhelm the buyer.", timestamp: 0.2, duration: 1.6),
            SpeechSegment(text: "A better approach is to lead with the problem that is already costing them money.", timestamp: 3.2, duration: 2.0)
        ]

        let contentType = transcriber.detectTranscriptionContentType(
            visualSlides: visualSlides,
            speech: speech,
            duration: 6.0
        )

        XCTAssertEqual(contentType, .voiceoverPlusText)
    }

    func testDetectTranscriptionContentTypeDoesNotPromoteLyricStyleSpeechToVoiceover() {
        let transcriber = InstagramAutoTranscriber.shared
        let visualSlides = [
            TranscriptSlide(text: "dancing in the dark", slideNumber: 1, timestamp: 0.0, endTimestamp: 1.0, source: .visionOCR),
            TranscriptSlide(text: "dancing in the dark", slideNumber: 2, timestamp: 1.0, endTimestamp: 2.0, source: .visionOCR),
            TranscriptSlide(text: "with you between my arms", slideNumber: 3, timestamp: 2.0, endTimestamp: 3.0, source: .visionOCR),
            TranscriptSlide(text: "barefoot on the grass", slideNumber: 4, timestamp: 3.0, endTimestamp: 4.0, source: .visionOCR)
        ]
        let speech = [
            SpeechSegment(text: "dancing in the dark", timestamp: 0.1, duration: 0.6),
            SpeechSegment(text: "dancing in the dark", timestamp: 1.1, duration: 0.6),
            SpeechSegment(text: "with you between my arms", timestamp: 2.1, duration: 0.7),
            SpeechSegment(text: "barefoot on the grass", timestamp: 3.1, duration: 0.7)
        ]

        let contentType = transcriber.detectTranscriptionContentType(
            visualSlides: visualSlides,
            speech: speech,
            duration: 4.0
        )

        XCTAssertEqual(contentType, .textOnly)
    }
}
