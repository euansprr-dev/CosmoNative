import XCTest
@testable import CosmoOS

/// The heal sweep's candidacy law, pinned:
/// - State-derived, never history: status + units + age decide.
/// - Pages heal by re-render (needs a URL); frames heal by re-analysis
///   (needs units). Posts belong to the worker's ladder; flows and notes
///   have nothing to decompose.
/// - An iPhone-captured page ("pending", no decomposer of its own) is a
///   candidate — the Mac is its processor.
/// - The "she sells" state (frame, partial, fully-transcribed units from a
///   pre-genre build) is a candidate; a completed swipe never is.
/// - The ledger bounds spend: three strikes, an hour apart, cleared on
///   success.
@MainActor
final class SwipeArtifactHealSweepTests: XCTestCase {

    // MARK: - Builders

    private func pageSwipe(
        status: String?,
        url: String? = "https://example.com/pricing",
        ageMinutes: Double = 30
    ) -> Atom {
        var atom = Atom.new(type: .research, title: "A page")
        atom.updateResearchMetadata { meta in
            meta.isSwipeFile = true
            meta.contentSource = SwipeKind.page.rawValue
            meta.processingStatus = status
            meta.url = url
        }
        atom = atom.withSwipeArtifact(SwipeArtifact(
            kind: .page, units: [], captureMode: "test", capturedURL: url
        ))
        atom.updatedAt = ISO8601.string(from: Date().addingTimeInterval(-ageMinutes * 60))
        return atom
    }

    private func frameSwipe(status: String?, ageMinutes: Double = 30, unitCount: Int = 5) -> Atom {
        var atom = Atom.new(type: .research, title: "she sells")
        atom.updateResearchMetadata { meta in
            meta.isSwipeFile = true
            meta.contentSource = SwipeKind.frame.rawValue
            meta.processingStatus = status
        }
        let units = (0..<unitCount).map {
            SwipeArtifactUnit(index: $0, attachmentUUID: UUID().uuidString)
        }
        atom = atom.withSwipeArtifact(SwipeArtifact(kind: .frame, units: units, captureMode: "test"))
        atom.updatedAt = ISO8601.string(from: Date().addingTimeInterval(-ageMinutes * 60))
        return atom
    }

    // MARK: - Pages

    func testPendingIPhonePageIsACandidate() {
        let action = SwipeArtifactHealSweep.healAction(for: pageSwipe(status: "pending"), now: Date())
        XCTAssertEqual(action, .decomposePage(url: "https://example.com/pricing"))
    }

    func testPartialAndFailedAndStuckExtractingPagesHeal() {
        for status in ["partial", "extraction_failed", "extracting"] {
            XCTAssertNotNil(
                SwipeArtifactHealSweep.healAction(for: pageSwipe(status: status), now: Date()),
                "status \(status) should be healable"
            )
        }
    }

    func testCompletePageIsNotACandidate() {
        XCTAssertNil(SwipeArtifactHealSweep.healAction(for: pageSwipe(status: "complete"), now: Date()))
    }

    func testYoungPageIsLeftToItsInFlightCapture() {
        let young = pageSwipe(status: "extracting", ageMinutes: 1)
        XCTAssertNil(SwipeArtifactHealSweep.healAction(for: young, now: Date()))
    }

    func testPageWithoutAnyURLCannotHeal() {
        XCTAssertNil(SwipeArtifactHealSweep.healAction(for: pageSwipe(status: "pending", url: nil), now: Date()))
    }

    func testPageURLFallsBackToMetadataWhenEnvelopeHasNone() {
        var atom = pageSwipe(status: "pending")
        var artifact = atom.swipeArtifact!
        artifact.capturedURL = nil
        atom = atom.withSwipeArtifact(artifact)
        XCTAssertEqual(
            SwipeArtifactHealSweep.healAction(for: atom, now: Date()),
            .decomposePage(url: "https://example.com/pricing")
        )
    }

    // MARK: - Frames

    func testSheSellsStateHeals() {
        // Frame, partial, units transcribed by a pre-genre build: one re-run
        // re-judges (and re-genres) it.
        let action = SwipeArtifactHealSweep.healAction(for: frameSwipe(status: "partial"), now: Date())
        XCTAssertEqual(action, .reanalyzeFrames)
    }

    func testRecentAnalyzingFrameIsLeftAlone() {
        XCTAssertNil(SwipeArtifactHealSweep.healAction(for: frameSwipe(status: "analyzing", ageMinutes: 2), now: Date()))
    }

    func testStuckAnalyzingFrameHeals() {
        XCTAssertEqual(
            SwipeArtifactHealSweep.healAction(for: frameSwipe(status: "analyzing", ageMinutes: 30), now: Date()),
            .reanalyzeFrames
        )
    }

    func testCompleteFrameNeverReanalyzesButMayClassify() {
        // Complete = the expensive craft pass never re-runs. An unfiled
        // complete frame gets the CHEAP genre classify instead (the backfill
        // arm); a filed one is fully at rest.
        XCTAssertEqual(
            SwipeArtifactHealSweep.healAction(for: frameSwipe(status: "complete"), now: Date()),
            .classifyGenre
        )
        var filed = frameSwipe(status: "complete")
        filed = filed.withSwipeGenre(.ad)
        XCTAssertNil(SwipeArtifactHealSweep.healAction(for: filed, now: Date()))
    }

    func testFrameWithoutUnitsCannotReanalyze() {
        XCTAssertNil(SwipeArtifactHealSweep.healAction(for: frameSwipe(status: "partial", unitCount: 0), now: Date()))
    }

    // MARK: - Out of scope

    func testPostsFlowsNotesAndForeignRowsAreNeverCandidates() {
        var post = Atom.new(type: .research, title: "A post")
        post.updateResearchMetadata { meta in
            meta.isSwipeFile = true
            meta.processingStatus = "partial"
        }
        XCTAssertNil(SwipeArtifactHealSweep.healAction(for: post, now: Date()))

        var note = Atom.new(type: .research, title: "A note")
        note.updateResearchMetadata { meta in
            meta.isSwipeFile = true
            meta.contentSource = SwipeKind.note.rawValue
            meta.processingStatus = "partial"
        }
        XCTAssertNil(SwipeArtifactHealSweep.healAction(for: note, now: Date()))

        var plain = Atom.new(type: .research, title: "Not a swipe")
        plain.updateResearchMetadata { $0.processingStatus = "partial" }
        XCTAssertNil(SwipeArtifactHealSweep.healAction(for: plain, now: Date()))

        var deleted = pageSwipe(status: "pending")
        deleted.isDeleted = true
        XCTAssertNil(SwipeArtifactHealSweep.healAction(for: deleted, now: Date()))
    }

    // MARK: - Ledger

    func testLedgerBoundsAttemptsAndSpacing() {
        var ledger = SwipeHealLedger()
        let now = Date()
        let uuid = "abc"

        XCTAssertTrue(ledger.mayAttempt(uuid, now: now, maxAttempts: 3, spacing: 3600))
        ledger.recordAttempt(uuid, now: now)
        // Too soon after an attempt.
        XCTAssertFalse(ledger.mayAttempt(uuid, now: now.addingTimeInterval(60), maxAttempts: 3, spacing: 3600))
        // An hour later is fine…
        XCTAssertTrue(ledger.mayAttempt(uuid, now: now.addingTimeInterval(3700), maxAttempts: 3, spacing: 3600))
        ledger.recordAttempt(uuid, now: now.addingTimeInterval(3700))
        ledger.recordAttempt(uuid, now: now.addingTimeInterval(7400))
        // …but the third strike is the last, forever.
        XCTAssertFalse(ledger.mayAttempt(uuid, now: now.addingTimeInterval(999_999), maxAttempts: 3, spacing: 3600))
        // Success clears the strikes.
        ledger.clear(uuid)
        XCTAssertTrue(ledger.mayAttempt(uuid, now: now, maxAttempts: 3, spacing: 3600))
    }
}
