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

    func testCarouselImageCachePersistsLocalImageSourcesByStableKey() async throws {
        let key = "ig-carousel-unit-\(UUID().uuidString)-0"
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(key).png")
        let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
        try imageData.write(to: sourceURL)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            if let cachedURL = InstagramCarouselImageCache.cachedFileURL(for: key) {
                try? FileManager.default.removeItem(at: cachedURL)
            }
        }

        let cachedData = await InstagramCarouselImageCache.imageData(for: sourceURL, stableKey: key)

        XCTAssertNotNil(cachedData)
        let cachedURL = InstagramCarouselImageCache.cachedFileURL(for: key)
        XCTAssertNotNil(cachedURL)
        XCTAssertTrue(cachedURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
    }

    func testLegacyPostThumbnailFallbackDoesNotMasqueradeAsLaterCarouselSlides() async throws {
        let shortcode = "unit-\(UUID().uuidString)"
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(shortcode).png")
        let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
        try imageData.write(to: sourceURL)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            if let legacyURL = InstagramCarouselImageCache.cachedFileURL(for: shortcode) {
                try? FileManager.default.removeItem(at: legacyURL)
            }
        }

        _ = await InstagramCarouselImageCache.imageData(for: sourceURL, stableKey: shortcode)

        XCTAssertNotNil(InstagramCarouselImageCache.fallbackImage(forStableKey: "ig-carousel-\(shortcode)-0"))
        XCTAssertNil(InstagramCarouselImageCache.fallbackImage(forStableKey: "ig-carousel-\(shortcode)-1"))
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

    func testDetectTranscriptionContentTypePrefersVoiceoverForOversegmentedCaptionBurst() {
        let transcriber = InstagramAutoTranscriber.shared
        let captionFragments = [
            "YEAH, FOR SUREL",
            "RENT BUY AT ALL FIVE? 00",
            "SO IF YOU HAVE $12,000 N",
            "$12.000 SO F YOU HAVE $12,000 IN $12",
            "$1200 YOUR BANK"
        ]
        let visualSlides = (0..<72).map { index in
            let text: String
            if index % 6 == 0 {
                text = captionFragments[(index / 6) % captionFragments.count]
            } else {
                text = """
                Investor portal dashboard \(index) View Hitory Dockmarks Probles Wadow Menu \
                parcel id \(90000 + index) lot sqft \(1200 + index) zoning map liens taxes escrow \
                underwriting tab seller phone browser chrome address valuation rehab photos
                """
            }
            return TranscriptSlide(
                text: text,
                slideNumber: index + 1,
                timestamp: Double(index) * 0.55,
                endTimestamp: Double(index) * 0.55 + 0.35,
                source: .geminiVision
            )
        }
        let speech = [
            SpeechSegment(
                text: """
                How many properties could I buy if I have twelve thousand dollars in my bank account right now? Yeah, for sure. \
                I can get you this turnkey Section 8 rental in Memphis Tennessee for sixty five thousand dollars. \
                We are going to end up doing a DSCR loan with fifteen percent down, which is going to be ninety seven fifty out of your pocket. \
                Then the bank covers the rest of the purchase and the Section 8 rent creates the cash flow.
                """,
                timestamp: 0.2,
                duration: 27.0
            )
        ]

        let contentType = transcriber.detectTranscriptionContentType(
            visualSlides: visualSlides,
            speech: speech,
            duration: 40.0
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

    // MARK: - Media Resolution Policy (display vs completeness)

    /// Regression: the April "≥2-slide complete" rule conflated "is it complete?"
    /// with "is there anything to show?". A single-slide /p/ carousel must stay
    /// flagged incomplete (so the background upgrade keeps trying) yet remain
    /// DISPLAYABLE so the teardown view never dead-ends on "Carousel images not loaded".
    func testSingleSlidePostIsDisplayableEvenWhileIncomplete() {
        let url = URL(string: "https://www.instagram.com/p/ABC123/")!
        let media = InstagramMediaData(
            originalURL: url,
            contentType: .carousel,
            carouselItems: [CarouselItem(index: 0, mediaType: .image, mediaURL: URL(string: "https://scontent.cdninstagram.com/slide0.jpg")!)]
        )

        XCTAssertTrue(
            InstagramMediaResolution.isIncompletePostMedia(mediaData: media, sourceURL: url),
            "A 1-slide /p/ carousel should still be treated as incomplete so the background resolver keeps upgrading it."
        )
        XCTAssertTrue(
            InstagramMediaResolution.isDisplayablePostMedia(mediaData: media),
            "A 1-slide /p/ carousel must be displayable — showing one real slide beats a 'not loaded' dead-end."
        )
    }

    func testThumbnailOnlyPostIsDisplayable() {
        let url = URL(string: "https://www.instagram.com/p/ABC123/")!
        let media = InstagramMediaData(
            originalURL: url,
            contentType: .carousel,
            thumbnailURL: URL(string: "https://scontent.cdninstagram.com/cover.jpg")!
        )

        XCTAssertTrue(InstagramMediaResolution.isDisplayablePostMedia(mediaData: media))
    }

    func testVideoPostIsDisplayable() {
        let url = URL(string: "https://www.instagram.com/reel/XYZ789/")!
        let media = InstagramMediaData(
            originalURL: url,
            contentType: .reel,
            videoURL: URL(string: "https://scontent.cdninstagram.com/video.mp4")!
        )

        XCTAssertTrue(InstagramMediaResolution.isDisplayablePostMedia(mediaData: media))
    }

    func testEmptyExtractionIsNotDisplayable() {
        let url = URL(string: "https://www.instagram.com/p/ABC123/")!
        let media = InstagramMediaData(originalURL: url, contentType: .carousel)

        XCTAssertFalse(
            InstagramMediaResolution.isDisplayablePostMedia(mediaData: media),
            "With no slides, no video, and no thumbnail there is genuinely nothing to show."
        )
    }

    func testCompleteCarouselIsBothDisplayableAndComplete() {
        let url = URL(string: "https://www.instagram.com/p/ABC123/")!
        let items = (0..<3).map {
            CarouselItem(index: $0, mediaType: .image, mediaURL: URL(string: "https://scontent.cdninstagram.com/slide\($0).jpg")!)
        }
        let media = InstagramMediaData(
            originalURL: url,
            contentType: .carousel,
            carouselItems: items,
            expectedCarouselItemCount: 3
        )

        XCTAssertFalse(InstagramMediaResolution.isIncompletePostMedia(mediaData: media, sourceURL: url))
        XCTAssertTrue(InstagramMediaResolution.isDisplayablePostMedia(mediaData: media))
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

    func testDetectTranscriptionContentTypePrefersVoiceoverWhenLongCaptionsMirrorSpeechDespiteTimingDrift() {
        let transcriber = InstagramAutoTranscriber.shared
        let captions = [
            "The fastest way to improve your offer is to remove every confusing promise",
            "Then show one concrete outcome your buyer can picture before they click",
            "That keeps the reel moving without turning every caption into a separate idea",
            "End with the next tiny action instead of explaining the whole strategy"
        ]
        let visualSlides = captions.enumerated().map { index, text in
            TranscriptSlide(
                text: text,
                slideNumber: index + 1,
                timestamp: Double(index) * 2.0,
                endTimestamp: Double(index + 1) * 2.0,
                source: .geminiVision
            )
        }
        let speech = captions.enumerated().map { index, text in
            SpeechSegment(
                text: text,
                timestamp: Double(index) * 2.0 + 2.7,
                duration: 0.4
            )
        }

        let contentType = transcriber.detectTranscriptionContentType(
            visualSlides: visualSlides,
            speech: speech,
            duration: 10.0
        )

        XCTAssertEqual(contentType, .voiceoverOnly)
    }

    func testMergeGeminiBatchResultsDropsDuplicateSlidesEvenWhenTimestampsDoNotOverlap() {
        let transcriber = InstagramAutoTranscriber.shared
        let hook = TranscriptSlide(
            text: "Stop making every reel caption become a separate swipe slide",
            slideNumber: 1,
            timestamp: 0.0,
            endTimestamp: 1.0,
            source: .geminiVision
        )
        let body = TranscriptSlide(
            text: "Keep the authored slide text once and put the voiceover transcript in one place",
            slideNumber: 2,
            timestamp: 1.2,
            endTimestamp: 2.4,
            source: .geminiVision
        )
        let duplicatedBody = TranscriptSlide(
            text: "Keep the authored slide text once and put the voiceover transcript in one place",
            slideNumber: 1,
            timestamp: 8.0,
            endTimestamp: 9.0,
            source: .geminiVision
        )

        let merged = transcriber.mergeGeminiBatchResults(
            batches: [[hook, body], [duplicatedBody]]
        )

        XCTAssertEqual(merged.map(\.text), [hook.text, body.text])
        XCTAssertEqual(merged.map(\.slideNumber), [1, 2])
    }

    func testMergeVisualSlidesWithSpeechKeepsUnalignedVoiceoverAsSingleTranscriptSlide() {
        let transcriber = InstagramAutoTranscriber.shared
        let speech = (0..<8).map { index in
            SpeechSegment(
                text: "This is sentence \(index) of a longer voiceover that should stay in one transcript card instead of being split into artificial swipe slides.",
                timestamp: Double(index) * 2.0,
                duration: 1.5
            )
        }

        let merged = transcriber.mergeVisualSlidesWithSpeech(
            visualSlides: [],
            speech: speech,
            allowSpeechAlignment: false
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, speech.map(\.text).joined(separator: " "))
        XCTAssertEqual(merged[0].source, .speechAudio)
    }

    func testTranscribeCarouselIgnoresDuplicateMediaItems() async throws {
        let transcriber = InstagramAutoTranscriber.shared
        let key = "ig-carousel-duplicate-\(UUID().uuidString)"
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(key).png")
        let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
        try imageData.write(to: sourceURL)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            if let firstCachedURL = InstagramCarouselImageCache.cachedFileURL(for: "ig-carousel-\(key)-0") {
                try? FileManager.default.removeItem(at: firstCachedURL)
            }
            if let secondCachedURL = InstagramCarouselImageCache.cachedFileURL(for: "ig-carousel-\(key)-1") {
                try? FileManager.default.removeItem(at: secondCachedURL)
            }
        }

        let items = [
            CarouselItem(index: 0, mediaType: .image, mediaURL: sourceURL),
            CarouselItem(index: 1, mediaType: .image, mediaURL: sourceURL)
        ]

        let result = await transcriber.transcribeCarousel(items: items, shortcode: key) { _ in }

        XCTAssertEqual(result.rawSlides.count, 1)
    }
}
