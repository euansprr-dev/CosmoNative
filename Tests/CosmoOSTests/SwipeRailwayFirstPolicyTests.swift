import XCTest
@testable import CosmoOS

/// Railway-first ownership policy: the cloud worker is the primary pipeline
/// for instagram/youtube/twitter swipes; the Mac is strictly the fallback
/// tier. These tests pin down exactly when the Mac may step in — and that
/// Mac metadata writes never destroy the worker's bookkeeping keys.
final class SwipeRailwayFirstPolicyTests: XCTestCase {

    private func metaJSON(_ dict: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return String(data: data, encoding: .utf8)!
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    // MARK: - Worker scope (must mirror cosmo-cloud-agent inWorkerScope)

    func testCloudWorkerScope() {
        XCTAssertTrue(SwipeProcessingService.isCloudWorkerScoped(
            url: "https://www.instagram.com/p/Dalun2ODxrf/", contentSource: "instagram_post"))
        XCTAssertTrue(SwipeProcessingService.isCloudWorkerScoped(
            url: "https://youtu.be/NgeyFln7RGk?si=x", contentSource: "youtube"))
        XCTAssertTrue(SwipeProcessingService.isCloudWorkerScoped(
            url: "https://x.com/user/status/1", contentSource: nil))
        XCTAssertTrue(SwipeProcessingService.isCloudWorkerScoped(
            url: "https://twitter.com/user/status/1", contentSource: "twitter"))
        XCTAssertFalse(SwipeProcessingService.isCloudWorkerScoped(
            url: "https://example.com/article", contentSource: "website"))
        XCTAssertFalse(SwipeProcessingService.isCloudWorkerScoped(
            url: "https://www.tiktok.com/@u/video/1", contentSource: "tiktok"))
        XCTAssertTrue(SwipeProcessingService.isCloudWorkerScoped(url: nil, contentSource: "instagram_post"),
            "contentSource alone qualifies — the URL may live in structured.sourceUrl")
        XCTAssertFalse(SwipeProcessingService.isCloudWorkerScoped(url: nil, contentSource: nil))
    }

    // MARK: - Pending: worker gets a grace window

    func testFreshPendingInstagramSwipeBelongsToTheWorker() {
        let now = Date()
        let json = metaJSON([
            "isSwipeFile": true,
            "url": "https://www.instagram.com/p/ABC/",
            "contentSource": "instagram_post",
            "processingStatus": "pending",
        ])
        XCTAssertFalse(SwipeProcessingService.macMayProcess(
            metadataJSON: json, updatedAt: now.addingTimeInterval(-30), now: now),
            "a just-captured pending swipe is the worker's — the Mac must wait")
        XCTAssertTrue(SwipeProcessingService.macMayProcess(
            metadataJSON: json, updatedAt: now.addingTimeInterval(-15 * 60), now: now),
            "a pending swipe the worker ignored past the grace window falls to the Mac")
        XCTAssertFalse(SwipeProcessingService.macMayProcess(
            metadataJSON: json, updatedAt: nil, now: now),
            "unknown age: stay conservative, leave it to the worker")
    }

    func testPendingWebsiteSwipeIsAlwaysTheMacs() {
        let now = Date()
        let json = metaJSON([
            "isSwipeFile": true,
            "url": "https://example.com/essay",
            "contentSource": "website",
            "processingStatus": "pending",
        ])
        XCTAssertTrue(SwipeProcessingService.macMayProcess(
            metadataJSON: json, updatedAt: now, now: now))
    }

    // MARK: - In-flight: live claims block, stale claims release

    func testLiveCloudClaimBlocksTheMac() {
        let now = Date()
        let json = metaJSON([
            "url": "https://www.instagram.com/p/ABC/",
            "contentSource": "instagram_post",
            "processingStatus": "transcribing",
            "processingWorker": "cloud",
            "processingClaimedAt": iso(now.addingTimeInterval(-60)),
        ])
        XCTAssertFalse(SwipeProcessingService.macMayProcess(metadataJSON: json, updatedAt: now, now: now))
    }

    func testStaleCloudClaimReleasesToTheMac() {
        let now = Date()
        let json = metaJSON([
            "url": "https://www.instagram.com/p/ABC/",
            "contentSource": "instagram_post",
            "processingStatus": "transcribing",
            "processingWorker": "cloud",
            "processingClaimedAt": iso(now.addingTimeInterval(-20 * 60)),
        ])
        XCTAssertTrue(SwipeProcessingService.macMayProcess(metadataJSON: json, updatedAt: now, now: now))
    }

    // MARK: - Failed/partial: respect the worker's retry budget

    func testFailedSwipeMidBackoffStaysWithTheWorker() {
        let now = Date()
        let json = metaJSON([
            "url": "https://youtu.be/abc123def",
            "contentSource": "youtube",
            "processingStatus": "extraction_failed",
            "processingWorker": "cloud",
            "cloudRetryCount": 2,
            "processingRetryAfter": iso(now.addingTimeInterval(45 * 60)),
        ])
        XCTAssertFalse(SwipeProcessingService.macMayProcess(metadataJSON: json, updatedAt: now, now: now),
            "the worker scheduled its own retry — the Mac must not preempt it")
    }

    func testWorkerMissingItsRetryWindowReleasesToTheMac() {
        let now = Date()
        let json = metaJSON([
            "url": "https://youtu.be/abc123def",
            "contentSource": "youtube",
            "processingStatus": "extraction_failed",
            "processingWorker": "cloud",
            "cloudRetryCount": 2,
            "processingRetryAfter": iso(now.addingTimeInterval(-10 * 60)),
        ])
        XCTAssertTrue(SwipeProcessingService.macMayProcess(metadataJSON: json, updatedAt: now, now: now),
            "retryAfter passed by more than the grace window: the worker is down")
    }

    func testExhaustedCloudRetryBudgetReleasesToTheMac() {
        let now = Date()
        let json = metaJSON([
            "url": "https://youtu.be/abc123def",
            "contentSource": "youtube",
            "processingStatus": "extraction_failed",
            "processingWorker": "cloud",
            "cloudRetryCount": 5,
            "processingRetryAfter": iso(now.addingTimeInterval(24 * 3600)),
        ])
        XCTAssertTrue(SwipeProcessingService.macMayProcess(metadataJSON: json, updatedAt: now, now: now))
    }

    // MARK: - Complete detection (the discard-local-result guard)

    func testIsCloudComplete() {
        XCTAssertTrue(SwipeProcessingService.isCloudComplete(metadataJSON: metaJSON([
            "processingStatus": "complete", "processingWorker": "cloud",
        ])))
        XCTAssertFalse(SwipeProcessingService.isCloudComplete(metadataJSON: metaJSON([
            "processingStatus": "complete",
        ])), "a Mac-completed swipe is not a cloud completion")
        XCTAssertFalse(SwipeProcessingService.isCloudComplete(metadataJSON: metaJSON([
            "processingStatus": "transcribing", "processingWorker": "cloud",
        ])))
        XCTAssertFalse(SwipeProcessingService.isCloudComplete(metadataJSON: nil))
    }

    // MARK: - Metadata writes must not destroy the worker's keys

    func testResearchMetadataSetterPreservesCloudWorkerKeys() {
        var atom = Atom.new(type: .research, title: "Swipe")
        atom.metadata = metaJSON([
            "isSwipeFile": true,
            "url": "https://www.instagram.com/p/ABC/",
            "processingStatus": "extraction_failed",
            "processingWorker": "cloud",
            "cloudRetryCount": 3,
            "processingRetryAfter": "2026-07-10T07:21:17.839Z",
            "carouselImageStorageURLs": ["https://cdn.example/0.jpg", "https://cdn.example/1.jpg"],
            "videoStorageURL": "https://cdn.example/video.mp4",
        ])

        atom.processingStatus = "extracting"

        let data = atom.metadata!.data(using: .utf8)!
        let meta = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(meta["processingStatus"] as? String, "extracting")
        XCTAssertEqual(meta["processingWorker"] as? String, "cloud",
            "the worker's claim key must survive a Mac status write")
        XCTAssertEqual((meta["cloudRetryCount"] as? NSNumber)?.intValue, 3,
            "wiping the retry counter restarts the worker's backoff from zero — the retry-war bug")
        XCTAssertEqual(meta["processingRetryAfter"] as? String, "2026-07-10T07:21:17.839Z")
        XCTAssertEqual((meta["carouselImageStorageURLs"] as? [String])?.count, 2)
        XCTAssertEqual(meta["videoStorageURL"] as? String, "https://cdn.example/video.mp4")
        XCTAssertEqual(meta["url"] as? String, "https://www.instagram.com/p/ABC/")
    }

    func testResearchMetadataSetterStillClearsExplicitNils() {
        var atom = Atom.new(type: .research, title: "Swipe")
        atom.metadata = metaJSON([
            "isSwipeFile": true,
            "url": "https://example.com",
            "summary": "old summary",
            "processingWorker": "cloud",
        ])

        atom.summary = nil

        let data = atom.metadata!.data(using: .utf8)!
        let meta = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(meta["summary"], "explicitly nilled fields must actually clear")
        XCTAssertEqual(meta["processingWorker"] as? String, "cloud")
    }
}
