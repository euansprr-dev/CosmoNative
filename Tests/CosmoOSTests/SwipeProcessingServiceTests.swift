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
}
