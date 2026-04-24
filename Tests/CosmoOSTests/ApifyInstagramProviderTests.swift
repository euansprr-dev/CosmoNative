import XCTest
@testable import CosmoOS

final class ApifyInstagramProviderTests: XCTestCase {
    func testParsePostExtractsCarouselItemsFromNestedSidecarPayload() {
        let provider = ApifyInstagramProvider.shared

        let json: [String: Any] = [
            "id": "post-1",
            "shortCode": "ABC123",
            "url": "https://www.instagram.com/p/ABC123/",
            "type": "carousel",
            "ownerUsername": "creator",
            "displayUrl": "https://cdn.example.com/thumb.jpg",
            "sidecarData": [
                "items": [
                    [
                        "type": "image",
                        "displayUrl": "https://cdn.example.com/1.jpg"
                    ],
                    [
                        "type": "video",
                        "displayUrl": "https://cdn.example.com/2-thumb.jpg",
                        "videoUrl": "https://cdn.example.com/2.mp4"
                    ]
                ]
            ]
        ]

        let post = provider.parsePost(json, ownerUsername: "creator")

        XCTAssertEqual(post?.contentType, .carousel)
        XCTAssertEqual(post?.carouselMediaCount, 2)
        XCTAssertEqual(post?.carouselItems?.count, 2)
        XCTAssertEqual(post?.carouselItems?.first?.mediaURL.absoluteString, "https://cdn.example.com/1.jpg")
        XCTAssertEqual(post?.carouselItems?.last?.mediaURL.absoluteString, "https://cdn.example.com/2.mp4")
        XCTAssertEqual(post?.carouselItems?.last?.mediaType, .video)
    }

    func testParsePostTreatsMissingCarouselChildrenAsIncomplete() {
        let provider = ApifyInstagramProvider.shared

        let json: [String: Any] = [
            "id": "post-2",
            "shortCode": "XYZ999",
            "url": "https://www.instagram.com/p/XYZ999/",
            "type": "carousel",
            "ownerUsername": "creator",
            "displayUrl": "https://cdn.example.com/thumb.jpg",
            "imagesCount": 4
        ]

        let post = provider.parsePost(json, ownerUsername: "creator")

        XCTAssertEqual(post?.contentType, .carousel)
        XCTAssertEqual(post?.carouselMediaCount, 4)
        XCTAssertNil(post?.carouselItems)
    }
}
