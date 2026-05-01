import XCTest
@testable import CosmoOS

final class ApifyInstagramProviderTests: XCTestCase {
    func testFetchPostUsesDetailedDataForDirectCarouselFallback() throws {
        let input = ApifyInstagramProvider.postActorInput(
            for: try XCTUnwrap(URL(string: "https://www.instagram.com/p/ABC123/"))
        )

        XCTAssertEqual(input["resultsLimit"] as? Int, 1)
        XCTAssertEqual(input["dataDetailLevel"] as? String, "detailedData")
        XCTAssertEqual(input["username"] as? [String], ["https://www.instagram.com/p/ABC123/"])
    }

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

    func testParsePostExtractsCarouselItemsFromApifyImageURLArray() {
        let provider = ApifyInstagramProvider.shared

        let json: [String: Any] = [
            "id": "post-images",
            "shortCode": "IMG123",
            "url": "https://www.instagram.com/p/IMG123/",
            "type": "carousel",
            "ownerUsername": "creator",
            "displayUrl": "https://cdn.example.com/thumb.jpg",
            "images": [
                "https://cdn.example.com/1.jpg",
                "https://cdn.example.com/2.jpg",
                "https://cdn.example.com/3.jpg"
            ]
        ]

        let post = provider.parsePost(json, ownerUsername: "creator")

        XCTAssertEqual(post?.carouselMediaCount, 3)
        XCTAssertEqual(post?.carouselItems?.map(\.mediaURL.absoluteString), [
            "https://cdn.example.com/1.jpg",
            "https://cdn.example.com/2.jpg",
            "https://cdn.example.com/3.jpg"
        ])
    }

    func testParsePostExtractsCarouselItemsFromApifyMediaURLDictionaries() {
        let provider = ApifyInstagramProvider.shared

        let json: [String: Any] = [
            "id": "post-media",
            "shortCode": "MEDIA123",
            "url": "https://www.instagram.com/p/MEDIA123/",
            "type": "carousel",
            "ownerUsername": "creator",
            "displayUrl": "https://cdn.example.com/thumb.jpg",
            "carouselMedia": [
                [
                    "mediaUrl": "https://cdn.example.com/1.jpg"
                ],
                [
                    "type": "video",
                    "url": "https://cdn.example.com/2-thumb.jpg",
                    "videoUrlDownload": "https://cdn.example.com/2.mp4"
                ]
            ]
        ]

        let post = provider.parsePost(json, ownerUsername: "creator")

        XCTAssertEqual(post?.carouselMediaCount, 2)
        XCTAssertEqual(post?.carouselItems?.first?.mediaURL.absoluteString, "https://cdn.example.com/1.jpg")
        XCTAssertEqual(post?.carouselItems?.last?.mediaURL.absoluteString, "https://cdn.example.com/2.mp4")
        XCTAssertEqual(post?.carouselItems?.last?.mediaType, .video)
    }

    func testParsePostStoresSingleKnownImageCountAsConfirmedSingleImage() {
        let provider = ApifyInstagramProvider.shared

        let json: [String: Any] = [
            "id": "post-single",
            "shortCode": "SINGLE123",
            "url": "https://www.instagram.com/p/SINGLE123/",
            "type": "image",
            "ownerUsername": "creator",
            "displayUrl": "https://cdn.example.com/thumb.jpg",
            "imagesCount": "1"
        ]

        let post = provider.parsePost(json, ownerUsername: "creator")

        XCTAssertEqual(post?.contentType, .image)
        XCTAssertEqual(post?.carouselMediaCount, 1)
        XCTAssertNil(post?.carouselItems)
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
