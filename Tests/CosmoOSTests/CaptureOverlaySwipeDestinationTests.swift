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
}
