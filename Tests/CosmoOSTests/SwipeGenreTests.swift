import XCTest
@testable import CosmoOS

/// The genre spine's laws, pinned:
/// - DERIVE-NEVER-MIGRATE — every swipe answers `swipeGenre` with zero backfill
///   (hint → envelope → kind default, total).
/// - CLOSED-VOCABULARY — `resolve` lands on a real case or nil, never a label.
/// - The hint's absence rule — a genre equal to the kind default clears the
///   metadata key, so "nothing decided" stays distinguishable.
/// - Seeds are state, not prose — URL/host facts, then measured page shape.
/// - Scope: the home stream is posts-only; genre rooms scope to one medium;
///   SEARCH LIFTS genre scope but never board scope.
final class SwipeGenreTests: XCTestCase {

    // MARK: - Builders

    private func swipeAtom(
        url: String? = nil,
        thumbnailUrl: String? = nil,
        body: String? = nil
    ) -> Atom {
        var atom = Atom.new(type: .research, title: "A swipe", body: body)
        atom.updateResearchMetadata { meta in
            meta.isSwipeFile = true
            meta.url = url
            meta.thumbnailUrl = thumbnailUrl
        }
        return atom
    }

    private func makeItem(
        title: String,
        kind: SwipeKind = .post,
        genre: SwipeGenre? = nil,
        boardIDs: [String] = []
    ) -> SwipeGalleryItem {
        SwipeGalleryItem(
            atomUUID: UUID().uuidString,
            title: title,
            boardIDs: boardIDs,
            kind: kind,
            genre: genre
        )
    }

    // MARK: - Defaults are total

    func testEveryKindHasAStructuralDefault() {
        XCTAssertEqual(SwipeGenre.defaultGenre(for: .post), .post)
        XCTAssertEqual(SwipeGenre.defaultGenre(for: .page), .page)
        XCTAssertEqual(SwipeGenre.defaultGenre(for: .frame), .screenshot)
        XCTAssertEqual(SwipeGenre.defaultGenre(for: .flow), .funnel)
        XCTAssertEqual(SwipeGenre.defaultGenre(for: .note), .copy)
    }

    /// The whole pre-spine library: no hint, no envelope — posts, genre post.
    func testLegacyPostSwipeDerivesPostGenreWithNoStorage() {
        let atom = swipeAtom(
            url: "https://www.instagram.com/reel/ABC/",
            thumbnailUrl: "https://cdn.example/thumb.jpg"
        )
        XCTAssertEqual(atom.swipeGenre, .post)
        XCTAssertNil(atom.researchMetadata?.swipeGenre, "legacy rows must stay hint-free")
    }

    func testPageWithoutVerdictDerivesPageFallback() {
        let atom = swipeAtom(url: "https://example.com/whatever")
            .withSwipeArtifact(SwipeArtifact(kind: .page))
        XCTAssertEqual(atom.swipeGenre, .page)
        XCTAssertNil(atom.researchMetadata?.swipeGenre, "a fallback genre never writes a hint")
    }

    // MARK: - Ladder order

    func testEnvelopeGenreBeatsKindDefault() {
        let atom = swipeAtom(url: "https://example.com/issue-42")
            .withSwipeArtifact(SwipeArtifact(kind: .page, genre: .newsletter))
        XCTAssertEqual(atom.swipeGenre, .newsletter)
    }

    func testMetadataHintBeatsEnvelope() {
        var atom = swipeAtom(url: "https://example.com/x")
            .withSwipeArtifact(SwipeArtifact(kind: .page, genre: .landingPage))
        atom.updateResearchMetadata { $0.swipeGenre = "salesPage" }
        XCTAssertEqual(atom.swipeGenre, .salesPage, "the hint is tier 1 — cheapest read wins")
    }

    // MARK: - withSwipeGenre (hint absence rule + lock)

    func testWithSwipeGenreWritesEnvelopeAndHintTogether() {
        let atom = swipeAtom(url: "https://example.com/p")
            .withSwipeArtifact(SwipeArtifact(kind: .page))
            .withSwipeGenre(.newsletter)
        XCTAssertEqual(atom.swipeArtifact?.genre, .newsletter)
        XCTAssertEqual(atom.researchMetadata?.swipeGenre, "newsletter")
    }

    func testFilingBackToTheStructuralFallbackClearsTheHint() {
        let atom = swipeAtom(url: "https://example.com/p")
            .withSwipeArtifact(SwipeArtifact(kind: .page, genre: .newsletter))
            .withSwipeGenre(.page)
        XCTAssertNil(atom.researchMetadata?.swipeGenre,
                     "absence means 'nothing decided' — a default write must clear the key")
        XCTAssertEqual(atom.swipeGenre, .page, "the envelope still answers through the ladder")
    }

    func testHandFilingLocksTheGenre() {
        let atom = swipeAtom(url: "https://example.com/p")
            .withSwipeArtifact(SwipeArtifact(kind: .page))
            .withSwipeGenre(.ad, lockedByUser: true)
        XCTAssertTrue(atom.swipeGenreIsLocked)
        XCTAssertEqual(atom.swipeGenre, .ad)
    }

    /// Posts have no envelope and never mint one — a filed post carries the
    /// hint alone. (The lock is envelope-borne and therefore moot for posts,
    /// which is fine: posts never run the artifact analyzer.)
    func testFilingAPostWritesHintOnly() {
        let atom = swipeAtom(url: "https://www.instagram.com/p/ABC/", thumbnailUrl: "t")
            .withSwipeGenre(.ad, lockedByUser: true)
        XCTAssertNil(atom.swipeArtifact, "DERIVE-NEVER-MIGRATE: no envelope is minted")
        XCTAssertEqual(atom.researchMetadata?.swipeGenre, "ad")
        XCTAssertEqual(atom.swipeGenre, .ad)
    }

    // MARK: - resolve (closed vocabulary)

    func testResolveAcceptsExactAndSeparatorInsensitiveForms() {
        XCTAssertEqual(SwipeGenre.resolve("landingPage"), .landingPage)
        XCTAssertEqual(SwipeGenre.resolve("Landing Pages"), .landingPage)
        XCTAssertEqual(SwipeGenre.resolve("SALES_PAGE"), .salesPage)
        XCTAssertEqual(SwipeGenre.resolve("Newsletter"), .newsletter)
    }

    func testResolveSynonymNet() {
        XCTAssertEqual(SwipeGenre.resolve("email"), .newsletter)
        XCTAssertEqual(SwipeGenre.resolve("opt-in"), .landingPage)
        XCTAssertEqual(SwipeGenre.resolve("VSL"), .salesPage)
        XCTAssertEqual(SwipeGenre.resolve("checkout"), .salesPage)
        XCTAssertEqual(SwipeGenre.resolve("ad creative"), .ad)
        XCTAssertEqual(SwipeGenre.resolve("email sequence"), .funnel)
        XCTAssertEqual(SwipeGenre.resolve("video script"), .script)
        XCTAssertEqual(SwipeGenre.resolve("headline"), .copy)
    }

    func testResolveRefusesToInventALabel() {
        XCTAssertNil(SwipeGenre.resolve("thought leadership artifact"))
        XCTAssertNil(SwipeGenre.resolve(""))
        XCTAssertNil(SwipeGenre.resolve(nil))
    }

    /// An unknown genre from a NEWER build decodes as nil and the ladder falls
    /// back to the kind default — never a wrong-but-confident space, never a
    /// failed artifact decode.
    func testUnknownStoredGenreDecodesAsNilNotAsFailure() throws {
        let json = """
        {"kind":"page","units":[],"genre":"holographicBrochure","artifactVersion":1}
        """
        let artifact = try JSONDecoder().decode(SwipeArtifact.self, from: Data(json.utf8))
        XCTAssertEqual(artifact.kind, .page)
        XCTAssertNil(artifact.genre)
    }

    // MARK: - Seeds

    func testNewsletterHostsSeedNewsletter() {
        XCTAssertEqual(SwipeGenreSeed.infer(url: "https://stratechery.substack.com/p/the-post"), .newsletter)
        XCTAssertEqual(SwipeGenreSeed.infer(url: "https://www.beehiiv.com/some/issue"), .newsletter)
        XCTAssertEqual(SwipeGenreSeed.infer(url: "https://mailchi.mp/brand/campaign-123"), .newsletter)
        XCTAssertEqual(SwipeGenreSeed.infer(url: "https://us1.campaign-archive.com/?u=abc"), .newsletter)
    }

    func testAdLibrariesSeedAd() {
        XCTAssertEqual(SwipeGenreSeed.infer(url: "https://www.facebook.com/ads/library/?id=123"), .ad)
        XCTAssertEqual(SwipeGenreSeed.infer(url: "https://adstransparency.google.com/advertiser/AR1"), .ad)
    }

    func testCommercePathsSeedSalesPageNarrowly() {
        XCTAssertEqual(SwipeGenreSeed.infer(url: "https://tool.com/pricing"), .salesPage)
        XCTAssertEqual(SwipeGenreSeed.infer(url: "https://tool.com/checkout/step-2"), .salesPage)
        XCTAssertNil(SwipeGenreSeed.infer(url: "https://tool.com/pricing-strategy-guide"),
                     "a blog post ABOUT pricing must not seed salesPage")
    }

    func testUnknownURLsSeedNothing() {
        XCTAssertNil(SwipeGenreSeed.infer(url: "https://example.com/blog/post"))
        XCTAssertNil(SwipeGenreSeed.infer(url: "not a url"))
        XCTAssertNil(SwipeGenreSeed.infer(url: nil))
    }

    func testPageShapeSeeds() {
        var shape = SwipePageShape()
        shape.hasPricingTable = true
        XCTAssertEqual(SwipeGenreSeed.infer(shape: shape), .salesPage)

        var landing = SwipePageShape()
        landing.ctaCount = 2
        landing.paragraphCount = 4
        XCTAssertEqual(SwipeGenreSeed.infer(shape: landing), .landingPage)

        var article = SwipePageShape()
        article.ctaCount = 1
        article.paragraphCount = 20
        XCTAssertNil(SwipeGenreSeed.infer(shape: article),
                     "a page that is neither falls through to the analyzer")
    }

    // MARK: - Receipt

    func testReceiptNamesTheGenre() {
        let receipt = SwipeIntakeReceipt(
            kind: .page, unitCount: 14, atomUUID: "x", genre: .newsletter
        )
        XCTAssertEqual(receipt.message, "Swiped · Newsletter · 14 sections")
    }

    func testReceiptFallsBackToTheKindDefaultName() {
        let receipt = SwipeIntakeReceipt(kind: .frame, unitCount: 3, atomUUID: "x")
        XCTAssertEqual(receipt.message, "Swiped · Screenshot · 3 images")
    }

    // MARK: - Scope

    func testHomeScopeIsPostsOnly() {
        let items = [
            makeItem(title: "A reel", kind: .post),
            makeItem(title: "An issue", kind: .page, genre: .newsletter),
            makeItem(title: "A funnel", kind: .flow),
        ]
        let visible = SwipeLibraryFiltering.filteredItems(
            from: items, scope: .home, filters: SwipeLibraryFilterState(),
            query: "", sortMode: .recent
        )
        XCTAssertEqual(visible.map(\.title), ["A reel"])
    }

    func testGenreRoomScopesToOneMedium() {
        let items = [
            makeItem(title: "A reel", kind: .post),
            makeItem(title: "Issue 42", kind: .page, genre: .newsletter),
            makeItem(title: "A sales page", kind: .page, genre: .salesPage),
        ]
        let visible = SwipeLibraryFiltering.filteredItems(
            from: items, scope: .genre(.newsletter), filters: SwipeLibraryFilterState(),
            query: "", sortMode: .recent
        )
        XCTAssertEqual(visible.map(\.title), ["Issue 42"])
    }

    /// Finding beats browsing: a query typed in the posts room must reach
    /// every space, or search reads as data loss.
    func testSearchLiftsGenreScope() {
        let items = [
            makeItem(title: "Fear hook reel", kind: .post),
            makeItem(title: "Fear-based issue", kind: .page, genre: .newsletter),
        ]
        let visible = SwipeLibraryFiltering.filteredItems(
            from: items, scope: .home, filters: SwipeLibraryFilterState(),
            query: "fear", sortMode: .recent
        )
        XCTAssertEqual(visible.count, 2, "the newsletter must surface from the posts room")
    }

    /// Searching a board is an intentional narrowing — it never lifts.
    func testSearchDoesNotLiftBoardScope() {
        let items = [
            makeItem(title: "Fear hook reel", kind: .post, boardIDs: ["b1"]),
            makeItem(title: "Fear-based issue", kind: .page, genre: .newsletter),
        ]
        let visible = SwipeLibraryFiltering.filteredItems(
            from: items, scope: .board("b1"), filters: SwipeLibraryFilterState(),
            query: "fear", sortMode: .recent
        )
        XCTAssertEqual(visible.map(\.title), ["Fear hook reel"])
    }

    func testGenreFacetFiltersConjunctively() {
        let items = [
            makeItem(title: "Issue 42", kind: .page, genre: .newsletter),
            makeItem(title: "A sales page", kind: .page, genre: .salesPage),
        ]
        var filters = SwipeLibraryFilterState()
        filters.genres = [.salesPage]
        let visible = SwipeLibraryFiltering.filteredItems(
            from: items, scope: .all, filters: filters, query: "", sortMode: .recent
        )
        XCTAssertEqual(visible.map(\.title), ["A sales page"])
    }

    /// Genre rides the searchable text — "newsletter" finds the newsletters
    /// even when no title mentions the word.
    func testGenreNameIsSearchable() {
        let items = [
            makeItem(title: "Issue 42", kind: .page, genre: .newsletter),
            makeItem(title: "A reel", kind: .post),
        ]
        let visible = SwipeLibraryFiltering.filteredItems(
            from: items, scope: .all, filters: SwipeLibraryFilterState(),
            query: "newsletter", sortMode: .recent
        )
        XCTAssertEqual(visible.map(\.title), ["Issue 42"])
    }
}
