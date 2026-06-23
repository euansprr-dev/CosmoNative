import XCTest
@testable import CosmoOS

final class SwipeProcessingServiceTests: XCTestCase {
    func testThumbnailFallbackIsDisabledForLikelyCarouselPostURL() {
        let mediaData = InstagramMediaData(
            originalURL: URL(string: "https://www.instagram.com/p/ABC123/")!,
            contentType: .image,
            thumbnailURL: URL(string: "https://cdn.example.com/thumb.jpg"),
            extractedAt: Date()
        )

        let shouldFallback = SwipeProcessingService.shouldUseThumbnailFallback(
            mediaData: mediaData,
            sourceURL: mediaData.originalURL
        )

        XCTAssertFalse(shouldFallback)
    }

    func testThumbnailFallbackIsAllowedForConfirmedSingleImagePost() {
        let mediaData = InstagramMediaData(
            originalURL: URL(string: "https://www.instagram.com/p/ABC123/")!,
            contentType: .image,
            thumbnailURL: URL(string: "https://cdn.example.com/thumb.jpg"),
            expectedCarouselItemCount: 1,
            extractedAt: Date()
        )

        let shouldFallback = InstagramMediaResolution.shouldUseThumbnailFallback(
            mediaData: mediaData,
            sourceURL: mediaData.originalURL
        )

        XCTAssertTrue(shouldFallback)
    }

    func testThumbnailFallbackIsDisabledWhenExpectedCarouselSlidesAreMissing() {
        let mediaData = InstagramMediaData(
            originalURL: URL(string: "https://www.instagram.com/p/ABC123/")!,
            contentType: .carousel,
            thumbnailURL: URL(string: "https://cdn.example.com/thumb.jpg"),
            expectedCarouselItemCount: 4,
            extractedAt: Date()
        )

        let shouldFallback = InstagramMediaResolution.shouldUseThumbnailFallback(
            mediaData: mediaData,
            sourceURL: mediaData.originalURL
        )

        XCTAssertFalse(shouldFallback)
    }

    func testThumbnailFallbackIsDisabledForCarouselTypedSingleThumbnailWithoutItems() {
        let mediaData = InstagramMediaData(
            originalURL: URL(string: "https://www.instagram.com/p/ABC123/")!,
            contentType: .carousel,
            thumbnailURL: URL(string: "https://cdn.example.com/random-slide.jpg"),
            expectedCarouselItemCount: 1,
            extractedAt: Date()
        )

        let shouldFallback = InstagramMediaResolution.shouldUseThumbnailFallback(
            mediaData: mediaData,
            sourceURL: mediaData.originalURL
        )

        XCTAssertFalse(shouldFallback)
        XCTAssertTrue(
            InstagramMediaResolution.isIncompletePostMedia(
                mediaData: mediaData,
                sourceURL: mediaData.originalURL
            )
        )
    }

    func testSingleUnconfirmedCarouselItemIsStillIncompleteForPostURL() {
        let postURL = URL(string: "https://www.instagram.com/p/ABC123/")!
        let mediaData = InstagramMediaData(
            originalURL: postURL,
            contentType: .carousel,
            thumbnailURL: URL(string: "https://cdn.example.com/thumb.jpg"),
            carouselItems: [
                CarouselItem(
                    index: 0,
                    mediaType: .image,
                    mediaURL: URL(string: "https://cdn.example.com/first.jpg")!
                )
            ],
            extractedAt: Date()
        )

        XCTAssertTrue(
            InstagramMediaResolution.isIncompletePostMedia(
                mediaData: mediaData,
                sourceURL: postURL
            )
        )
    }

    func testThumbnailFallbackRemainsEnabledForNonCarouselImageURL() {
        let mediaData = InstagramMediaData(
            originalURL: URL(string: "https://www.instagram.com/stories/example/123/")!,
            contentType: .image,
            thumbnailURL: URL(string: "https://cdn.example.com/thumb.jpg"),
            extractedAt: Date()
        )

        let shouldFallback = SwipeProcessingService.shouldUseThumbnailFallback(
            mediaData: mediaData,
            sourceURL: mediaData.originalURL
        )

        XCTAssertTrue(shouldFallback)
    }

    func testOneSlidePostWithoutConfirmedSingleImageMetadataIsReprocessed() {
        let shouldSkip = SwipeProcessingService.shouldSkipExistingTranscript(
            sourceURL: URL(string: "https://www.instagram.com/p/ABC123/")!,
            transcriptStatus: "available",
            transcriptSlideCount: 1,
            carouselItemCount: nil,
            expectedCarouselItemCount: nil
        )

        XCTAssertFalse(shouldSkip)
    }

    func testConfirmedSingleImagePostWithOneSlideIsSkipped() {
        let shouldSkip = SwipeProcessingService.shouldSkipExistingTranscript(
            sourceURL: URL(string: "https://www.instagram.com/p/ABC123/")!,
            transcriptStatus: "available",
            transcriptSlideCount: 1,
            carouselItemCount: nil,
            expectedCarouselItemCount: 1
        )

        XCTAssertTrue(shouldSkip)
    }

    func testCarouselIsSkippedOnlyWhenTranscriptCoversKnownItemCount() {
        let postURL = URL(string: "https://www.instagram.com/p/ABC123/")!

        XCTAssertFalse(
            SwipeProcessingService.shouldSkipExistingTranscript(
                sourceURL: postURL,
                transcriptStatus: "available",
                transcriptSlideCount: 1,
                carouselItemCount: 4,
                expectedCarouselItemCount: 4
            )
        )

        XCTAssertTrue(
            SwipeProcessingService.shouldSkipExistingTranscript(
                sourceURL: postURL,
                transcriptStatus: "available",
                transcriptSlideCount: 4,
                carouselItemCount: 4,
                expectedCarouselItemCount: 4
            )
        )
    }

    func testOneSlideCarouselMetadataDoesNotSkipReprocessing() {
        let shouldSkip = SwipeProcessingService.shouldSkipExistingTranscript(
            sourceURL: URL(string: "https://www.instagram.com/p/ABC123/")!,
            transcriptStatus: "available",
            transcriptSlideCount: 1,
            carouselItemCount: 1,
            expectedCarouselItemCount: 1
        )

        XCTAssertFalse(shouldSkip)
    }

    func testSwipeAnalysisDecodesLegacyMinimalPayloadWithDefaultVersionState() throws {
        let legacyJSON = """
        {
          "hookText": null,
          "frameworkType": null,
          "hookType": null,
          "swipeContentFormat": "carousel"
        }
        """

        let analysis = try JSONDecoder().decode(SwipeAnalysis.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(analysis.swipeContentFormat, .carousel)
        XCTAssertEqual(analysis.analysisVersion, 1)
        XCTAssertFalse(analysis.isFullyAnalyzed)
    }
}
