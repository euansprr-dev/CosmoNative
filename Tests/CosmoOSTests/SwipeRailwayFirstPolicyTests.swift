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

    // MARK: - SCOPE-TWIN: no non-post kind is ever worker-scoped

    /// The worker has no extractor for a screenshot, a captured web page, a
    /// funnel or a pasted headline. If it ever claims one it fails extraction
    /// and burns the whole retry ladder — so the kind gate runs FIRST and
    /// unconditionally, ahead of every URL and contentSource match.
    func testNonPostKindsAreNeverWorkerScoped() {
        for kind in SwipeKind.allCases where kind != .post {
            XCTAssertFalse(
                SwipeProcessingService.isCloudWorkerScoped(
                    url: "https://www.instagram.com/p/Dalun2ODxrf/",
                    contentSource: "instagram_post",
                    swipeKind: kind.rawValue
                ),
                "\(kind.rawValue) must be Mac-owned even when its URL and source look cloud-scoped"
            )
            XCTAssertFalse(kind.isCloudProcessable, "\(kind.rawValue) must not be cloud-processable")
        }
    }

    /// A page swipe OF a YouTube URL is still a page swipe. This is the exact
    /// case the kind-first ordering exists for.
    func testPageSwipeOfACloudScopedURLStaysWithTheMac() {
        XCTAssertFalse(SwipeProcessingService.isCloudWorkerScoped(
            url: "https://www.youtube.com/@creator",
            contentSource: "youtube",
            swipeKind: SwipeKind.page.rawValue))
        XCTAssertTrue(SwipeProcessingService.isCloudWorkerScoped(
            url: "https://www.youtube.com/watch?v=abc123",
            contentSource: "youtube",
            swipeKind: SwipeKind.post.rawValue),
            "an explicit post kind must not narrow the worker's existing scope")
    }

    /// Legacy rows carry no `swipeKind` key at all. Their scope must be
    /// byte-identical to what it was before the artifact spine existed.
    func testLegacySwipesWithoutAKindKeepTheirScope() {
        XCTAssertTrue(SwipeProcessingService.isCloudWorkerScoped(
            url: "https://www.instagram.com/reel/XYZ/", contentSource: nil, swipeKind: nil))
        XCTAssertFalse(SwipeProcessingService.isCloudWorkerScoped(
            url: "https://example.com/sales", contentSource: nil, swipeKind: nil))
    }

    /// An unrecognised kind (a row from a newer build) is Mac-owned on BOTH
    /// sides of the twin. The worker refuses it; if the Mac deferred to the
    /// worker instead, the swipe would sit pending forever with nobody
    /// processing it. Unknown ⇒ Mac is the only safe direction, because the
    /// Mac is the fallback tier for everything.
    ///
    /// Note this is deliberately STRICTER than `SwipeKind`'s tolerant decode,
    /// which reads an unknown kind as `.post` so the row still renders. The
    /// scope check compares the raw string for exactly this reason.
    func testUnknownKindIsMacOwnedOnBothSidesOfTheTwin() {
        XCTAssertFalse(SwipeProcessingService.isCloudWorkerScoped(
            url: "https://www.instagram.com/p/ABC/",
            contentSource: "instagram_post",
            swipeKind: "some_future_kind"))
        XCTAssertEqual(SwipeKind(rawValue: "some_future_kind"), nil)
    }

    /// An empty-string kind is treated as absent, not as an unknown kind — a
    /// blank JSON value must not strand a perfectly ordinary Instagram swipe.
    func testEmptyKindStringIsTreatedAsAbsent() {
        XCTAssertTrue(SwipeProcessingService.isCloudWorkerScoped(
            url: "https://www.instagram.com/p/ABC/",
            contentSource: "instagram_post",
            swipeKind: ""))
    }

    /// macMayProcess reads the kind out of metadata — a page swipe is never
    /// deferred to a worker that will not touch it.
    func testMacMayProcessNonPostKindsImmediately() {
        let json = metaJSON([
            "isSwipeFile": true,
            "url": "https://www.instagram.com/p/ABC/",
            "contentSource": "instagram_post",
            "swipeKind": SwipeKind.frame.rawValue,
            "processingStatus": "pending"
        ])
        XCTAssertTrue(
            SwipeProcessingService.macMayProcess(metadataJSON: json, updatedAt: Date()),
            "a frame swipe is Mac-owned: no cloud grace window applies"
        )
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

    func testWorkerMissingItsRetryWindowStillDoesNotReleaseToTheMac() {
        let now = Date()
        let json = metaJSON([
            "url": "https://youtu.be/abc123def",
            "contentSource": "youtube",
            "processingStatus": "extraction_failed",
            "processingWorker": "cloud",
            "cloudRetryCount": 2,
            "processingRetryAfter": iso(now.addingTimeInterval(-10 * 60)),
        ])
        XCTAssertFalse(SwipeProcessingService.macMayProcess(metadataJSON: json, updatedAt: now, now: now),
            "a missed retry window is not an invitation — the Mac picking this up is a duplicate paid pass")
    }

    /// Regression: this asserted `true` under the old policy, which is how a
    /// swipe the cloud had already spent five full pipeline passes on earned a
    /// sixth one locally, on every launch, wake and sync.
    func testExhaustedCloudRetryBudgetIsTerminalNotAHandoff() {
        let now = Date()
        let json = metaJSON([
            "url": "https://youtu.be/abc123def",
            "contentSource": "youtube",
            "processingStatus": "extraction_failed",
            "processingWorker": "cloud",
            "cloudRetryCount": 5,
            "processingRetryAfter": iso(now.addingTimeInterval(24 * 3600)),
        ])
        XCTAssertFalse(SwipeProcessingService.macMayProcess(metadataJSON: json, updatedAt: now, now: now),
            "exhausted means nobody retries automatically — it waits for a manual retry")
    }

    func testNeedsManualRetryIsNeverPickedUpAutomatically() {
        let now = Date()
        let json = metaJSON([
            "url": "https://www.instagram.com/p/ABC/",
            "contentSource": "instagram_post",
            "processingStatus": SwipeProcessingService.statusNeedsManualRetry,
            "processingWorker": "cloud",
            "cloudRetryCount": 2,
        ])
        // Age must not matter: the whole point is that time passing never revives it.
        XCTAssertFalse(SwipeProcessingService.macMayProcess(metadataJSON: json, updatedAt: now, now: now))
        XCTAssertFalse(SwipeProcessingService.macMayProcess(
            metadataJSON: json, updatedAt: now.addingTimeInterval(-48 * 3600), now: now),
            "a two-day-old retired swipe is still retired")
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

// MARK: - Manual-retry surfacing
//
// Retries are bounded to a short capture window, so the UI can no longer infer
// "still retrying" from the status string. These pin the derivation that decides
// whether a swipe shows a Retry control — get it wrong and a failed swipe is
// stranded with a spinner and no way forward.
@MainActor
extension SwipeRailwayFirstPolicyTests {

    private func swipeAtom(status: String, retryAfter: Date?) -> Atom {
        var atom = Atom.new(type: .research, title: "Swipe")
        var meta: [String: Any] = ["isSwipeFile": true, "processingStatus": status]
        if let retryAfter { meta["processingRetryAfter"] = iso(retryAfter) }
        atom.metadata = metaJSON(meta)
        return atom
    }

    func testRetiredSwipeAwaitsManualRetry() {
        let atom = swipeAtom(status: SwipeProcessingService.statusNeedsManualRetry, retryAfter: nil)
        XCTAssertTrue(SwipeStudyModel.awaitsManualRetry(atom))
    }

    func testFailedSwipeWithAFutureRetryIsStillWorking() {
        let atom = swipeAtom(status: "extraction_failed", retryAfter: Date().addingTimeInterval(90))
        XCTAssertFalse(SwipeStudyModel.awaitsManualRetry(atom),
            "a retry is genuinely scheduled inside the window — don't offer a manual one yet")
    }

    /// Every swipe that failed under the old 30/60/90-minute ladder is sitting in
    /// this exact state: a stale status with a retryAfter that has long passed and
    /// nothing left to honour it.
    func testFailedSwipeWithAPassedRetryAwaitsManualRetry() {
        let atom = swipeAtom(status: "extraction_failed", retryAfter: Date().addingTimeInterval(-2 * 3600))
        XCTAssertTrue(SwipeStudyModel.awaitsManualRetry(atom),
            "legacy backlog must surface a Retry rather than claiming it is still retrying")
    }

    func testPartialSwipeWithNoBookkeepingAwaitsManualRetry() {
        let atom = swipeAtom(status: "partial", retryAfter: nil)
        XCTAssertTrue(SwipeStudyModel.awaitsManualRetry(atom),
            "no scheduled retry at all means nothing is coming")
    }

    func testHealthySwipesNeverAwaitManualRetry() {
        for status in ["complete", "pending", "extracting", "transcribing", "analyzing"] {
            XCTAssertFalse(SwipeStudyModel.awaitsManualRetry(swipeAtom(status: status, retryAfter: nil)),
                "\(status) must not offer a manual retry")
        }
    }

    /// The copy and the control have to agree: anything that awaits a manual
    /// retry must also render a status line, or the Retry button has nowhere to live.
    func testAwaitingManualRetryAlwaysHasStatusCopy() {
        for status in ["extraction_failed", "partial", SwipeProcessingService.statusNeedsManualRetry] {
            XCTAssertNotNil(SwipeStudyModel.processingCopy(for: status),
                "\(status) awaits a retry but renders no status line to host the button")
        }
    }
}

// MARK: - Mac capture window
//
// The Mac scan runs on launch, wake and every sync. Anything it re-selects runs
// unattended, so a swipe that never reaches a terminal status must not stay
// eligible forever — six February clipboard captures were still being
// reprocessed in July, one analysis call each, every scan.
extension SwipeRailwayFirstPolicyTests {

    func testUnstampedSwipeIsAlwaysEligibleForItsFirstPass() {
        XCTAssertTrue(SwipeProcessingService.withinCaptureWindow(metadataJSON: metaJSON([
            "isSwipeFile": true, "processingStatus": "pending",
        ])), "the whole pre-existing library is unstamped — it must still get one pass")
        XCTAssertTrue(SwipeProcessingService.withinCaptureWindow(metadataJSON: nil))
    }

    func testFreshlyStampedSwipeIsStillEligible() {
        let now = Date()
        XCTAssertTrue(SwipeProcessingService.withinCaptureWindow(metadataJSON: metaJSON([
            "processingStatus": "pending",
            SwipeProcessingService.firstAttemptKey: iso(now.addingTimeInterval(-60)),
        ]), now: now))
    }

    func testStampedSwipeFallsOutOfTheWindow() {
        let now = Date()
        XCTAssertFalse(SwipeProcessingService.withinCaptureWindow(metadataJSON: metaJSON([
            "processingStatus": "pending",
            SwipeProcessingService.firstAttemptKey: iso(now.addingTimeInterval(-20 * 60)),
        ]), now: now), "past the window, only an explicit retry runs it")
        XCTAssertFalse(SwipeProcessingService.withinCaptureWindow(metadataJSON: metaJSON([
            "processingStatus": "pending",
            SwipeProcessingService.firstAttemptKey: iso(now.addingTimeInterval(-150 * 24 * 3600)),
        ]), now: now), "a five-month-old pending swipe must stop being rescanned")
    }

    func testUnparseableStampDoesNotStrandTheSwipe() {
        XCTAssertTrue(SwipeProcessingService.withinCaptureWindow(metadataJSON: metaJSON([
            "processingStatus": "pending",
            SwipeProcessingService.firstAttemptKey: "not-a-date",
        ])), "a corrupt stamp should fall back to allowing a pass, not silently drop the swipe")
    }
}

@MainActor
extension SwipeRailwayFirstPolicyTests {
    /// The moment the last attempt is spent, a Retry must appear — even though
    /// the worker left a future retryAfter behind that nothing will honour.
    func testExhaustedBudgetAwaitsManualRetryDespiteFutureRetryAfter() {
        var atom = Atom.new(type: .research, title: "Swipe")
        atom.metadata = metaJSON([
            "isSwipeFile": true,
            "processingStatus": "partial",
            "cloudRetryCount": SwipeProcessingService.cloudMaxRetries,
            "processingRetryAfter": iso(Date().addingTimeInterval(45 * 60)),
        ])
        XCTAssertTrue(SwipeStudyModel.awaitsManualRetry(atom))
    }
}
