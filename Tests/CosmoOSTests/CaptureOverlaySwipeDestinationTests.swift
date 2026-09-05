import XCTest
import UniformTypeIdentifiers
@testable import CosmoOS

/// The ⌥C overlay's swipe destination. The staged tray is the ONE place in the
/// system that asks the user anything kind-adjacent, so its inference, its
/// stickiness, and its never-lose-a-capture guarantee all need pinning.
@MainActor
final class CaptureOverlaySwipeDestinationTests: XCTestCase {

    private func staged(
        kind: MediaAttachmentKind,
        name: String = "shot.png"
    ) -> CaptureOverlayViewModel.StagedAttachment {
        CaptureOverlayViewModel.StagedAttachment(
            payload: .data(Data([0x89]), type: .png, suggestedName: name),
            displayName: name,
            kind: kind,
            fingerprint: nil
        )
    }

    // MARK: - Inference

    func testAllImagesDefaultToSwipe() {
        let tray = [staged(kind: .screenshot), staged(kind: .image), staged(kind: .screenshot)]
        XCTAssertEqual(CaptureOverlayViewModel.inferredStagedDestination(for: tray), .swipe)
    }

    func testASingleScreenshotDefaultsToSwipe() {
        XCTAssertEqual(
            CaptureOverlayViewModel.inferredStagedDestination(for: [staged(kind: .screenshot)]),
            .swipe)
    }

    /// A PDF invoice and three ad screenshots arrive through the identical
    /// gesture — a mix is genuinely ambiguous, so it goes to triage.
    func testAnyNonImageSendsTheTrayToTheInbox() {
        let mixed = [staged(kind: .screenshot), staged(kind: .pdf, name: "invoice.pdf")]
        XCTAssertEqual(CaptureOverlayViewModel.inferredStagedDestination(for: mixed), .inbox)
    }

    func testDocumentsDefaultToTheInbox() {
        for kind in [MediaAttachmentKind.pdf, .document, .audio, .video, .spreadsheet, .textFile] {
            XCTAssertEqual(
                CaptureOverlayViewModel.inferredStagedDestination(for: [staged(kind: kind)]),
                .inbox, "\(kind.rawValue) is not a swipe")
        }
    }

    func testEmptyTrayDefaultsToTheInbox() {
        XCTAssertEqual(CaptureOverlayViewModel.inferredStagedDestination(for: []), .inbox)
    }

    /// Page scans belong to the scan pipeline, not the swipe file — they are
    /// photographs OF paper, captured to be transcribed, not saved as craft.
    func testPageScansAreNotSwipes() {
        XCTAssertEqual(
            CaptureOverlayViewModel.inferredStagedDestination(for: [staged(kind: .pageScan)]),
            .inbox)
    }

    // MARK: - Stickiness

    func testAnExplicitChoiceSticks() {
        let model = CaptureOverlayViewModel()
        model.chooseStagedDestination(.inbox)
        XCTAssertEqual(model.stagedDestination, .inbox)
        // A picker that re-guesses under the user's hand is worse than none.
        model.chooseStagedDestination(.swipe)
        XCTAssertEqual(model.stagedDestination, .swipe)
    }

    func testANewSummonResetsTheChoice() {
        let model = CaptureOverlayViewModel()
        model.chooseStagedDestination(.swipe)
        model.beginSession(capturedFrom: "Safari")
        XCTAssertEqual(model.stagedDestination, .inbox, "a summon is a fresh session")
    }

    func testClearingTheTrayReleasesTheChoice() {
        let model = CaptureOverlayViewModel()
        model.chooseStagedDestination(.swipe)
        model.clearStaged()
        XCTAssertEqual(model.stagedDestination, .inbox)
    }

    // MARK: - The swipe alias

    func testSwipeAliasIsRecognisedCaseInsensitively() {
        XCTAssertEqual(
            CaptureOverlayViewModel.swipeAliasBody(in: "swipe: https://someone.com/sales"),
            "https://someone.com/sales")
        XCTAssertEqual(
            CaptureOverlayViewModel.swipeAliasBody(in: "SWIPE: a great hook"),
            "a great hook")
        XCTAssertEqual(
            CaptureOverlayViewModel.swipeAliasBody(in: "  Swipe:   spaced  "),
            "spaced")
    }

    func testNonAliasTextIsNotClaimed() {
        XCTAssertNil(CaptureOverlayViewModel.swipeAliasBody(in: "swiped that yesterday"))
        XCTAssertNil(CaptureOverlayViewModel.swipeAliasBody(in: "Groceries: milk"))
        XCTAssertNil(CaptureOverlayViewModel.swipeAliasBody(in: "a note about swipe: things"))
    }

    /// A bare `swipe:` with nothing after it is not a capture — there is
    /// nothing to save, and treating it as one would create an empty swipe.
    func testBareAliasWithNoBodyIsNotAnAlias() {
        XCTAssertNil(CaptureOverlayViewModel.swipeAliasBody(in: "swipe:"))
        XCTAssertNil(CaptureOverlayViewModel.swipeAliasBody(in: "swipe:   "))
    }

    // MARK: - Undo routing

    /// A swipe row carries an ATOM uuid. Routing it to
    /// `InboxRepository.dismiss` would silently no-op while the row reported
    /// itself undone — so the entry names its own target.
    func testSessionEntriesDefaultToTheInboxUndoTarget() {
        let entry = CaptureOverlayViewModel.SessionEntry(
            displayName: "a capture", kind: nil,
            state: .captured(itemUUID: "abc"), fingerprint: nil
        )
        if case .inboxItem = entry.undoTarget {} else {
            XCTFail("existing capture rows must keep dismissing inbox items")
        }
    }

    func testSwipeEntriesCarryTheSwipeUndoTarget() {
        let entry = CaptureOverlayViewModel.SessionEntry(
            displayName: "a swipe", kind: nil,
            state: .captured(itemUUID: "abc"), fingerprint: nil,
            destinationLabel: "→ Swipe File · Frame", undoTarget: .swipeAtom
        )
        if case .swipeAtom = entry.undoTarget {} else {
            XCTFail("a swipe row must delete its atom, not dismiss a nonexistent inbox item")
        }
    }

    // MARK: - The platform-link trigger

    /// Membership is by host: a permalink, a profile, a share link and a
    /// mobile/short host all offer the choice — the router still decides the
    /// kind. This is what makes TikTok work despite the classifier having no
    /// permalink pattern for it.
    func testPlatformLinksAreDetectedByHost() {
        let cases: [(String, CaptureSwipeLink.Platform)] = [
            ("https://www.instagram.com/p/C1a2b3/", .instagram),
            ("https://instagram.com/reel/XyZ/", .instagram),
            ("https://www.instagram.com/some.creator/p/CODE/", .instagram),
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", .youtube),
            ("https://youtu.be/dQw4w9WgXcQ", .youtube),
            ("https://youtube.com/shorts/abcdefghijk", .youtube),
            ("https://x.com/someone/status/1234567890", .x),
            ("https://twitter.com/someone/status/1234567890", .x),
            ("https://mobile.twitter.com/someone/status/1", .x),
            ("https://www.tiktok.com/@creator/video/7234567890123456789", .tiktok),
            ("https://vm.tiktok.com/ZMabcdef/", .tiktok),
            ("https://www.threads.net/@creator/post/AbC123", .threads),
            ("https://www.loom.com/share/abc123def456", .loom),
        ]
        for (url, platform) in cases {
            let link = CaptureSwipeLink.detect(in: url)
            XCTAssertEqual(link?.platform, platform, url)
            XCTAssertEqual(link?.url, url, "the link must be handed on exactly as written")
            XCTAssertNil(link?.note, "a bare link carries no note")
        }
    }

    func testOrdinaryLinksAndProseDoNotTrigger() {
        for text in [
            "https://example.com/sales-page",
            "https://someone.substack.com/p/issue-12",
            "a thought with no link in it",
            "",
            // A host that merely ends in the platform's letters is not it.
            "https://notx.com/a/status/1",
            "https://myinstagram.company.com/p/X",
        ] {
            XCTAssertNil(CaptureSwipeLink.detect(in: text), text)
        }
    }

    /// Strict on scheme, matching the router: a bare `instagram.com/…` typed
    /// in prose is a mention, not a capture.
    func testSchemelessMentionsDoNotTrigger() {
        XCTAssertNil(CaptureSwipeLink.detect(in: "saw it on instagram.com/p/ABC yesterday"))
        XCTAssertNil(CaptureSwipeLink.detect(in: "www.youtube.com/watch?v=dQw4w9WgXcQ"))
    }

    /// "link + thought" mirrors "screenshots + thought": the link is the
    /// swipe, the rest of the text is its note.
    func testTextAroundTheLinkBecomesTheNote() {
        let trailing = CaptureSwipeLink.detect(in: "https://www.instagram.com/p/C1a2b3/ love this hook")
        XCTAssertEqual(trailing?.url, "https://www.instagram.com/p/C1a2b3/")
        XCTAssertEqual(trailing?.note, "love this hook")

        let leading = CaptureSwipeLink.detect(in: "study the pacing\nhttps://youtu.be/dQw4w9WgXcQ")
        XCTAssertEqual(leading?.platform, .youtube)
        XCTAssertEqual(leading?.note, "study the pacing")
    }

    func testTheFirstPlatformLinkWins() {
        let link = CaptureSwipeLink.detect(
            in: "https://example.com/context then https://x.com/a/status/1 and https://instagram.com/p/Z")
        XCTAssertEqual(link?.platform, .x)
        XCTAssertEqual(link?.url, "https://x.com/a/status/1")
    }

    func testHostMatchingIsCaseInsensitiveAndSuffixBased() {
        XCTAssertEqual(CaptureSwipeLink.platform(forHost: "WWW.Instagram.COM"), .instagram)
        XCTAssertEqual(CaptureSwipeLink.platform(forHost: "m.youtube.com"), .youtube)
        XCTAssertNil(CaptureSwipeLink.platform(forHost: "instagram.com.evil.example"))
    }

    // MARK: - Link destination inference

    func testAPlatformLinkInTheFieldDefaultsToSwipe() {
        let model = CaptureOverlayViewModel()
        model.beginSession(capturedFrom: nil)
        model.captureText = "https://www.instagram.com/p/C1a2b3/"
        model.captureTextChanged()
        XCTAssertEqual(model.swipeLink?.platform, .instagram)
        XCTAssertEqual(model.stagedDestination, .swipe)
    }

    func testPlainTextInTheFieldStaysOnTheInbox() {
        let model = CaptureOverlayViewModel()
        model.beginSession(capturedFrom: nil)
        model.captureText = "remember to call the printer"
        model.captureTextChanged()
        XCTAssertNil(model.swipeLink)
        XCTAssertEqual(model.stagedDestination, .inbox)
    }

    func testAnOrdinaryLinkDoesNotChangeTheDefault() {
        let model = CaptureOverlayViewModel()
        model.beginSession(capturedFrom: nil)
        model.captureText = "https://example.com/pricing"
        model.captureTextChanged()
        XCTAssertNil(model.swipeLink)
        XCTAssertEqual(model.stagedDestination, .inbox)
    }

    /// The user flips the link to Inbox, then keeps editing the note — the
    /// toggle must not snap back under their hand.
    func testTheLinkChoiceSticksWhileTheLinkRemains() {
        let model = CaptureOverlayViewModel()
        model.beginSession(capturedFrom: nil)
        model.captureText = "https://x.com/someone/status/1"
        model.captureTextChanged()
        model.chooseStagedDestination(.inbox)
        model.captureText = "https://x.com/someone/status/1 read later"
        model.captureTextChanged()
        XCTAssertEqual(model.stagedDestination, .inbox)
    }

    /// The link leaving the field ends its tray: the next link is inferred
    /// afresh rather than inheriting a choice made for a different link.
    func testClearingTheLinkReleasesTheChoice() {
        let model = CaptureOverlayViewModel()
        model.beginSession(capturedFrom: nil)
        model.captureText = "https://x.com/someone/status/1"
        model.captureTextChanged()
        model.chooseStagedDestination(.inbox)
        model.captureText = ""
        model.captureTextChanged()
        XCTAssertEqual(model.stagedDestination, .inbox)
        model.captureText = "https://www.tiktok.com/@creator/video/7234567890123456789"
        model.captureTextChanged()
        XCTAssertEqual(model.stagedDestination, .swipe, "a fresh link starts from the default")
    }

    /// With files staged the tray is the subject and the field is its note —
    /// a link in the note never overrides the tray's own inference.
    func testAStagedTrayOutranksTheLinkInTheField() {
        let link = CaptureSwipeLink.detect(in: "https://www.instagram.com/p/C1a2b3/")
        XCTAssertEqual(
            CaptureOverlayViewModel.inferredDestination(
                staged: [staged(kind: .pdf, name: "invoice.pdf")], link: link),
            .inbox)
        XCTAssertEqual(
            CaptureOverlayViewModel.inferredDestination(staged: [staged(kind: .screenshot)], link: nil),
            .swipe)
        XCTAssertEqual(CaptureOverlayViewModel.inferredDestination(staged: [], link: link), .swipe)
        XCTAssertEqual(CaptureOverlayViewModel.inferredDestination(staged: [], link: nil), .inbox)
    }

    // MARK: - Drop preview

    func testAllImageDropsAnnounceTheSwipeDestinationBeforeRelease() {
        let preview = CaptureDragPreview(
            items: [.init(id: 0, name: "a.png", systemImage: "photo"),
                    .init(id: 1, name: "b.png", systemImage: "photo")],
            totalCount: 2, stagesOnDrop: true, isAllImages: true
        )
        XCTAssertTrue(preview.isAllImages)
        XCTAssertEqual(preview.totalCount, 2)
    }

    func testMixedDropsDoNotClaimToBeSwipes() {
        let preview = CaptureDragPreview(
            items: [.init(id: 0, name: "a.png", systemImage: "photo"),
                    .init(id: 1, name: "b.pdf", systemImage: "doc.richtext")],
            totalCount: 2, stagesOnDrop: true, isAllImages: false
        )
        XCTAssertFalse(preview.isAllImages)
    }

    /// A dragged platform link announces the swipe destination before release
    /// (it lands in the field with Swipe pre-selected); a plain link keeps
    /// its instant-capture promise.
    func testPlatformLinkDropsAnnounceTheSwipeDestination() {
        let platform = CaptureDragPreview(
            items: [.init(id: 0, name: "Instagram link", systemImage: "link")],
            totalCount: 1, stagesOnDrop: true, isSwipeLink: true
        )
        XCTAssertTrue(platform.isSwipeLink)
        let plain = CaptureDragPreview(
            items: [.init(id: 0, name: "example.com", systemImage: "link")],
            totalCount: 1
        )
        XCTAssertFalse(plain.isSwipeLink)
        XCTAssertFalse(plain.stagesOnDrop)
    }
}
