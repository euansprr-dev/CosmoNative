import XCTest
@testable import CosmoOS

@MainActor
final class InstagramExtractorTests: XCTestCase {
    func testBetterCarouselResultPrefersCandidateWithMoreSlides() {
        let extractor = InstagramExtractor.shared
        let originalURL = URL(string: "https://www.instagram.com/p/ABC123/")!

        let partial = InstagramMediaData(
            originalURL: originalURL,
            contentType: .carousel,
            thumbnailURL: URL(string: "https://cdn.example.com/thumb.jpg"),
            carouselItems: makeCarouselItems(count: 2, prefix: "https://cdn.example.com/partial"),
            extractedAt: Date()
        )
        let full = InstagramMediaData(
            originalURL: originalURL,
            contentType: .carousel,
            thumbnailURL: URL(string: "https://cdn.example.com/thumb.jpg"),
            carouselItems: makeCarouselItems(count: 10, prefix: "https://cdn.example.com/full"),
            extractedAt: Date()
        )

        let selected = extractor.betterCarouselResult(current: partial, candidate: full)

        XCTAssertEqual(selected.carouselItems?.count, 10)
        XCTAssertEqual(selected.carouselItems?.first?.mediaURL.absoluteString, "https://cdn.example.com/full/0.jpg")
    }

    func testBetterCarouselResultPrefersRefreshedURLsWhenSlideCountMatches() {
        let extractor = InstagramExtractor.shared
        let originalURL = URL(string: "https://www.instagram.com/p/ABC123/")!

        let stale = InstagramMediaData(
            originalURL: originalURL,
            contentType: .carousel,
            thumbnailURL: URL(string: "https://cdn.example.com/thumb.jpg"),
            carouselItems: makeCarouselItems(count: 3, prefix: "https://cdn.example.com/stale"),
            extractedAt: Date().addingTimeInterval(-3600)
        )
        let refreshed = InstagramMediaData(
            originalURL: originalURL,
            contentType: .carousel,
            thumbnailURL: URL(string: "https://cdn.example.com/thumb.jpg"),
            carouselItems: makeCarouselItems(count: 3, prefix: "https://cdn.example.com/fresh"),
            extractedAt: Date()
        )

        let selected = extractor.betterCarouselResult(current: stale, candidate: refreshed)

        XCTAssertEqual(selected.carouselItems?.count, 3)
        XCTAssertEqual(selected.carouselItems?.first?.mediaURL.absoluteString, "https://cdn.example.com/fresh/0.jpg")
    }

    func testBetterPartialResultPrefersRealCarouselItemsForPostURL() {
        let extractor = InstagramExtractor.shared
        let originalURL = URL(string: "https://www.instagram.com/p/ABC123/")!

        let thumbnailOnly = InstagramMediaData(
            originalURL: originalURL,
            contentType: .image,
            thumbnailURL: URL(string: "https://cdn.example.com/thumb.jpg"),
            authorUsername: "creator",
            caption: "partial metadata",
            extractedAt: Date()
        )
        let carousel = InstagramMediaData(
            originalURL: originalURL,
            contentType: .carousel,
            thumbnailURL: URL(string: "https://cdn.example.com/thumb.jpg"),
            carouselItems: makeCarouselItems(count: 2, prefix: "https://cdn.example.com/full"),
            extractedAt: Date()
        )

        let selected = extractor.betterPartialResult(current: thumbnailOnly, candidate: carousel)

        XCTAssertEqual(selected.carouselItems?.count, 2)
        XCTAssertEqual(selected.contentType, .carousel)
    }

    func testConfirmedSingleImageGraphQLResultIsNotCarouselTyped() throws {
        let extractor = InstagramExtractor.shared
        let originalURL = URL(string: "https://www.instagram.com/p/ABC123/")!
        let displayURL = "https://cdn.example.com/confirmed-single.jpg"

        let mediaData = try extractor.parseMediaObject(
            [
                "is_video": false,
                "display_url": displayURL
            ],
            originalURL: originalURL,
            baseType: .carousel,
            confirmedSidecarState: true
        )

        XCTAssertEqual(mediaData.expectedCarouselItemCount, 1)
        XCTAssertEqual(mediaData.contentType, .image)
        XCTAssertEqual(mediaData.thumbnailURL?.absoluteString, displayURL)
        XCTAssertNil(mediaData.carouselItems)
        XCTAssertFalse(
            InstagramMediaResolution.isIncompletePostMedia(
                mediaData: mediaData,
                sourceURL: originalURL
            )
        )
    }

    func testCarouselCacheDoesNotForceRefreshWhenFreshSlidesExist() {
        let cache = InstagramMediaCache.shared
        let postURL = URL(string: "https://www.instagram.com/p/ABC123/")!
        let cached = InstagramMediaData(
            originalURL: postURL,
            contentType: .carousel,
            thumbnailURL: URL(string: "https://cdn.example.com/thumb.jpg"),
            carouselItems: makeCarouselItems(count: 10, prefix: "https://cdn.example.com/full"),
            extractedAt: Date()
        )

        XCTAssertFalse(cache.shouldResolveBestCarouselMedia(for: postURL, cached: cached))
    }

    func testCarouselCacheRefreshesWhenCachedPostIsIncomplete() {
        let cache = InstagramMediaCache.shared
        let postURL = URL(string: "https://www.instagram.com/p/ABC123/")!
        let cached = InstagramMediaData(
            originalURL: postURL,
            contentType: .image,
            thumbnailURL: URL(string: "https://cdn.example.com/thumb.jpg"),
            extractedAt: Date()
        )

        XCTAssertTrue(cache.shouldResolveBestCarouselMedia(for: postURL, cached: cached))
    }

    func testCarouselCacheRefreshesCarouselTypedSingleThumbnailResult() {
        let cache = InstagramMediaCache.shared
        let postURL = URL(string: "https://www.instagram.com/p/ABC123/")!
        let cached = InstagramMediaData(
            originalURL: postURL,
            contentType: .carousel,
            thumbnailURL: URL(string: "https://cdn.example.com/random-slide.jpg"),
            expectedCarouselItemCount: 1,
            extractedAt: Date()
        )

        XCTAssertTrue(cache.shouldResolveBestCarouselMedia(for: postURL, cached: cached))
    }

    func testRecentIncompleteResultsStayInCooldownWindow() {
        let now = Date()
        let recentFailure = now.addingTimeInterval(-30)
        let oldFailure = now.addingTimeInterval(-120)

        XCTAssertTrue(
            InstagramMediaCache.shouldReuseRecentIncompleteCachedResult(
                lastAttemptAt: recentFailure,
                now: now
            )
        )
        XCTAssertFalse(
            InstagramMediaCache.shouldReuseRecentIncompleteCachedResult(
                lastAttemptAt: oldFailure,
                now: now
            )
        )
        XCTAssertFalse(
            InstagramMediaCache.shouldReuseRecentIncompleteCachedResult(
                lastAttemptAt: nil,
                now: now
            )
        )
    }

    private func makeCarouselItems(count: Int, prefix: String) -> [CarouselItem] {
        (0..<count).map { index in
            CarouselItem(
                index: index,
                mediaType: .image,
                mediaURL: URL(string: "\(prefix)/\(index).jpg")!
            )
        }
    }
}
