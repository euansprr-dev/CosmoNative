import XCTest
@testable import CosmoOS

/// DERIVE-NEVER-MIGRATE: every swipe answers `swipeKind` without a backfill
/// pass ever touching a row. These tests pin the derivation ladder — stored
/// metadata hint, then stored envelope, then the legacy shape — and pin that
/// the ~400 swipes predating the artifact spine all derive to `.post`.
final class SwipeKindDerivationTests: XCTestCase {

    // MARK: - Builders

    private func swipeAtom(
        url: String? = nil,
        thumbnailUrl: String? = nil,
        body: String? = nil,
        contentSource: String? = nil
    ) -> Atom {
        var atom = Atom.new(type: .research, title: "A swipe", body: body)
        atom.updateResearchMetadata { meta in
            meta.isSwipeFile = true
            meta.url = url
            meta.thumbnailUrl = thumbnailUrl
            meta.contentSource = contentSource
        }
        return atom
    }

    // MARK: - Legacy derivation

    func testLegacyInstagramSwipeDerivesPost() {
        let atom = swipeAtom(
            url: "https://www.instagram.com/reel/ABC/",
            thumbnailUrl: "https://cdn.example/thumb.jpg",
            contentSource: "instagram"
        )
        XCTAssertEqual(atom.swipeKind, .post)
        XCTAssertNil(atom.researchMetadata?.swipeKind, "legacy rows must stay hint-free")
    }

    /// A swipe with a link but no thumbnail yet (a pending capture) is still a
    /// post — the thumbnail arrives seconds later and the kind must not flicker.
    func testPendingSwipeWithNoThumbnailIsStillPost() {
        let atom = swipeAtom(url: "https://www.instagram.com/p/ABC/")
        XCTAssertEqual(atom.swipeKind, .post)
    }

    /// `swipeFromRawText`'s shape: text, no link, no image.
    func testRawTextSwipeDerivesNote() {
        let atom = swipeAtom(body: "The best hook I read all week.")
        XCTAssertEqual(atom.swipeKind, .note)
    }

    func testEmptySwipeWithNothingAtAllDerivesPost() {
        XCTAssertEqual(swipeAtom().swipeKind, .post, "the total fallback is .post")
    }

    /// A swipe whose only media is a thumbnail (a saved discover post with no
    /// stored URL) must not be mistaken for pasted text.
    func testThumbnailOnlySwipeDerivesPost() {
        let atom = swipeAtom(thumbnailUrl: "https://cdn.example/t.jpg", body: "caption text")
        XCTAssertEqual(atom.swipeKind, .post)
    }

    func testNonSwipeResearchAtomAnswersPost() {
        var atom = Atom.new(type: .research, title: "An article", body: "Long body")
        atom.updateResearchMetadata { $0.url = "https://example.com/article" }
        XCTAssertEqual(atom.swipeKind, .post, "a non-swipe never reports a real kind")
    }

    // MARK: - Stored kind wins

    func testStoredArtifactSetsBothEnvelopeAndMetadataHint() {
        let atom = swipeAtom(url: "https://example.com/sales")
            .withSwipeArtifact(SwipeArtifact(kind: .page, units: [
                SwipeArtifactUnit(index: 0, role: .hook, headline: "Stop guessing")
            ]))
        XCTAssertEqual(atom.swipeKind, .page)
        XCTAssertEqual(atom.researchMetadata?.swipeKind, "page",
                       "the metadata hint is what both halves of the SCOPE-TWIN read")
        XCTAssertEqual(atom.swipeArtifact?.units.count, 1)
    }

    /// The hint can be lost by an older build's partial merge; the envelope is
    /// the second rung of the ladder and must still answer correctly.
    func testEnvelopeAnswersWhenMetadataHintIsMissing() {
        var atom = swipeAtom(url: "https://example.com/sales")
            .withSwipeArtifact(SwipeArtifact(kind: .page))
        atom.updateResearchMetadata { $0.swipeKind = nil }
        XCTAssertNil(atom.researchMetadata?.swipeKind)
        XCTAssertEqual(atom.swipeKind, .page, "the envelope is the fallback for a lost hint")
    }

    /// `.post` deliberately clears the hint: absence has to keep meaning
    /// "derive me", or legacy rows stop being distinguishable from new ones.
    func testPostKindClearsTheMetadataHint() {
        var atom = swipeAtom(url: "https://www.instagram.com/p/ABC/")
        atom = atom.withSwipeKindMetadata(.frame)
        XCTAssertEqual(atom.researchMetadata?.swipeKind, "frame")
        atom = atom.withSwipeKindMetadata(.post)
        XCTAssertNil(atom.researchMetadata?.swipeKind)
        XCTAssertEqual(atom.swipeKind, .post)
    }

    func testUnknownStoredKindDecodesAsPost() {
        var atom = swipeAtom(url: "https://www.instagram.com/p/ABC/")
        atom.updateResearchMetadata { $0.swipeKind = "hologram" }
        XCTAssertEqual(atom.swipeKind, .post,
                       "a kind from a newer build must degrade, never crash or vanish")
    }

    // MARK: - Kind vocabulary

    func testOnlyPostIsCloudProcessable() {
        XCTAssertEqual(SwipeKind.allCases.filter(\.isCloudProcessable), [.post])
    }

    func testUnitCountLabelsReadNaturally() {
        XCTAssertEqual(SwipeKind.page.unitCountLabel(1), "1 section")
        XCTAssertEqual(SwipeKind.page.unitCountLabel(14), "14 sections")
        XCTAssertEqual(SwipeKind.frame.unitCountLabel(3), "3 images")
        XCTAssertEqual(SwipeKind.flow.unitCountLabel(1), "1 step")
    }

    // MARK: - Lens

    func testLegacySwipeCarriesOnlyTheSwipeLens() {
        let atom = swipeAtom(url: "https://www.instagram.com/p/ABC/")
        XCTAssertTrue(atom.hasSwipeLens)
        XCTAssertFalse(atom.hasResearchLens)
        XCTAssertEqual(atom.swipeLenses, [.swipe])
    }

    /// Every pre-lens research atom derives the research lens — no migration.
    func testLegacyResearchAtomDerivesTheResearchLens() {
        var atom = Atom.new(type: .research, title: "An article")
        atom.updateResearchMetadata { $0.url = "https://example.com/article" }
        XCTAssertFalse(atom.hasSwipeLens)
        XCTAssertTrue(atom.hasResearchLens)
    }

    func testLensesAreAdditive() {
        let atom = swipeAtom(url: "https://example.com/sales").addingLens(.research)
        XCTAssertEqual(atom.swipeLenses, [.swipe, .research],
                       "adding a lens must never remove the other one")
    }

    func testRemovingTheLastLensIsRefused() {
        let atom = swipeAtom(url: "https://www.instagram.com/p/ABC/")
        let stripped = atom.removingLens(.swipe)
        XCTAssertTrue(stripped.hasSwipeLens,
                      "a source with no lens is invisible everywhere — that is data loss")
    }

    func testRemovingOneOfTwoLensesWorks() {
        let both = swipeAtom(url: "https://example.com/sales").addingLens(.research)
        let swipeOnly = both.removingLens(.research)
        XCTAssertEqual(swipeOnly.swipeLenses, [.swipe])
    }
}
