import XCTest
@testable import CosmoOS

/// Swipe or research? The ladder decides on STATE — which surface it arrived
/// through, what platform it is, what shape the page measured, what you have
/// decided about this domain before — and only reads the capture's wording
/// last.
///
/// Per `feedback_no_bandaids`: the prose tier is a tiebreak, never the
/// mechanism. Adding a keyword fixes one capture; the tiers above fix a class.
@MainActor
final class SwipeLensRouterTests: XCTestCase {

    override func tearDown() {
        for host in ["example.com", "someone.com", "mixed.com"] {
            SwipeDomainPrior.shared.forget(host: host)
        }
        super.tearDown()
    }

    // MARK: - Tier order

    /// The surface is the strongest signal: the user already said what they
    /// meant by choosing where to put it.
    func testAnExplicitSwipeSurfaceBeatsEverythingBelowIt() {
        let verdict = SwipeLensRouter.inferLens(.init(
            explicitSwipeSurface: true,
            url: "https://example.com/a-long-article",
            prose: "great stat for the pitch",
            pageShape: SwipePageShape(ctaCount: 0, paragraphCount: 40)
        ))
        XCTAssertEqual(verdict.lens, .swipe)
        XCTAssertEqual(verdict.tier, .surface)
        XCTAssertEqual(verdict.reason, "You swiped it")
    }

    func testPlatformFamilyBeatsPageShapeAndProse() {
        let verdict = SwipeLensRouter.inferLens(.init(
            url: "https://www.instagram.com/reel/ABC/",
            prose: "useful stat",
            pageShape: SwipePageShape(paragraphCount: 40)
        ))
        XCTAssertEqual(verdict.lens, .swipe)
        XCTAssertEqual(verdict.tier, .platform)
        XCTAssertEqual(verdict.reason, "Instagram post")
    }

    func testEveryShortFormPlatformIsRecognised() {
        for (url, name) in [
            ("https://www.instagram.com/p/A/", "Instagram"),
            ("https://www.tiktok.com/@u/video/1", "TikTok"),
            ("https://www.youtube.com/shorts/abc", "YouTube Shorts"),
            ("https://x.com/u/status/1", "X"),
            ("https://twitter.com/u/status/1", "X"),
            ("https://www.threads.net/@u/post/A", "Threads")
        ] {
            XCTAssertEqual(SwipeLensRouter.platformFamily(of: url), name, url)
        }
        XCTAssertNil(SwipeLensRouter.platformFamily(of: "https://example.com/sales"))
        XCTAssertNil(
            SwipeLensRouter.platformFamily(of: "https://www.youtube.com/watch?v=abc"),
            "a long YouTube video is not automatically craft reference")
    }

    // MARK: - Page shape (the tier that separates a sales page from an article)

    func testAPricingTableMakesItASwipe() {
        let verdict = SwipeLensRouter.inferLens(.init(
            url: "https://someone.com/pricing",
            pageShape: SwipePageShape(ctaCount: 2, hasPricingTable: true, paragraphCount: 8)
        ))
        XCTAssertEqual(verdict.lens, .swipe)
        XCTAssertEqual(verdict.tier, .pageShape)
    }

    func testTestimonialsPlusAnAskMakeItASwipe() {
        let verdict = SwipeLensRouter.inferLens(.init(
            url: "https://someone.com/offer",
            pageShape: SwipePageShape(ctaCount: 1, testimonialCount: 4, paragraphCount: 10)
        ))
        XCTAssertEqual(verdict.lens, .swipe)
        XCTAssertEqual(verdict.reason, "4 testimonials and a call to action")
    }

    func testRepeatedAsksMakeItASwipe() {
        let verdict = SwipeLensRouter.inferLens(.init(
            url: "https://someone.com/offer",
            pageShape: SwipePageShape(ctaCount: 6, paragraphCount: 12)
        ))
        XCTAssertEqual(verdict.lens, .swipe)
        XCTAssertEqual(verdict.reason, "Asks 6 times")
    }

    /// The case the whole tier exists for: the same shape of URL as a sales
    /// page, but it is something to read.
    func testALongArticleWithNoAskIsResearch() {
        let verdict = SwipeLensRouter.inferLens(.init(
            url: "https://someone.com/essay",
            pageShape: SwipePageShape(ctaCount: 0, paragraphCount: 22)
        ))
        XCTAssertEqual(verdict.lens, .research)
        XCTAssertEqual(verdict.tier, .pageShape)
        XCTAssertEqual(verdict.reason, "22 paragraphs, no call to action")
    }

    /// A page that is neither shape falls THROUGH rather than being forced —
    /// the thresholds are deliberately far apart.
    func testAnAmbiguousPageFallsThroughToLaterTiers() {
        XCTAssertNil(SwipeLensRouter.verdict(for: SwipePageShape(ctaCount: 2, paragraphCount: 6)))
        XCTAssertNil(SwipeLensRouter.verdict(for: SwipePageShape()))
    }

    // MARK: - Domain prior

    func testAHostWithTooFewDecisionsHasNoPrior() {
        SwipeDomainPrior.shared.record(lens: .swipe, host: "example.com")
        SwipeDomainPrior.shared.record(lens: .swipe, host: "example.com")
        XCTAssertNil(
            SwipeDomainPrior.shared.verdict(forHost: "example.com"),
            "one accidental choice must not stamp every later capture")
    }

    func testAConsistentHostEarnsAPrior() {
        for _ in 0..<4 { SwipeDomainPrior.shared.record(lens: .swipe, host: "someone.com") }
        let verdict = SwipeDomainPrior.shared.verdict(forHost: "someone.com")
        XCTAssertEqual(verdict?.lens, .swipe)
        XCTAssertEqual(verdict?.tier, .domainPrior)
        XCTAssertEqual(verdict?.reason, "You swipe someone.com")
    }

    /// A host you have split down the middle is genuinely ambiguous, and the
    /// ladder must keep going rather than picking the majority by one.
    func testASplitHostHasNoPrior() {
        for _ in 0..<3 { SwipeDomainPrior.shared.record(lens: .swipe, host: "mixed.com") }
        for _ in 0..<3 { SwipeDomainPrior.shared.record(lens: .research, host: "mixed.com") }
        XCTAssertNil(SwipeDomainPrior.shared.verdict(forHost: "mixed.com"))
    }

    func testThePriorIsConsultedByTheLadder() {
        for _ in 0..<4 { SwipeDomainPrior.shared.record(lens: .research, host: "example.com") }
        let verdict = SwipeLensRouter.inferLens(.init(url: "https://www.example.com/anything"))
        XCTAssertEqual(verdict.lens, .research)
        XCTAssertEqual(verdict.tier, .domainPrior)
    }

    func testHostNormalisationStripsWWW() {
        XCTAssertEqual(SwipeLensRouter.host(of: "https://WWW.Example.com/path?x=1"), "example.com")
        XCTAssertEqual(SwipeLensRouter.host(of: "http://someone.com"), "someone.com")
        XCTAssertNil(SwipeLensRouter.host(of: "not a url"))
        XCTAssertNil(SwipeLensRouter.host(of: nil))
    }

    // MARK: - Prose (the LAST tier, never the mechanism)

    func testCraftWordsLeanSwipeAndClaimWordsLeanResearch() {
        XCTAssertEqual(SwipeLensRouter.proseVerdict("look at this hook")?.lens, .swipe)
        XCTAssertEqual(SwipeLensRouter.proseVerdict("great stat for the pitch")?.lens, .research)
    }

    /// Both vocabularies present is genuinely ambiguous — falling through beats
    /// letting whichever list happened to be checked first decide.
    func testMixedProseFallsThrough() {
        XCTAssertNil(SwipeLensRouter.proseVerdict("great hook, and a useful stat"))
    }

    func testNeutralProseFallsThrough() {
        XCTAssertNil(SwipeLensRouter.proseVerdict("saw this earlier"))
        XCTAssertNil(SwipeLensRouter.proseVerdict(""))
    }

    // MARK: - Fallback

    /// Research is the safer default for an unknown link: a wrongly-swiped
    /// article pollutes the reference library the writing engine draws on.
    func testAnUnknownLinkDefaultsToResearch() {
        let verdict = SwipeLensRouter.inferLens(.init(url: "https://unknown-domain-xyz.test/page"))
        XCTAssertEqual(verdict.lens, .research)
        XCTAssertEqual(verdict.tier, .fallback)
    }

    // MARK: - Lens duality

    func testAddingALensIsAdditiveAndReversible() {
        var atom = Atom.new(type: .research, title: "A source")
        atom.updateResearchMetadata { $0.isSwipeFile = true }
        XCTAssertEqual(atom.swipeLenses, [.swipe])

        atom = atom.addingLens(.research)
        XCTAssertEqual(atom.swipeLenses, [.swipe, .research],
                       "one source, two lenses — never a second row")

        atom = atom.removingLens(.research)
        XCTAssertEqual(atom.swipeLenses, [.swipe])
    }

    func testTheLastLensCannotBeRemoved() {
        var atom = Atom.new(type: .research, title: "A source")
        atom.updateResearchMetadata { $0.isSwipeFile = true }
        let stripped = atom.removingLens(.swipe)
        XCTAssertFalse(stripped.swipeLenses.isEmpty,
                       "a source with no lens is invisible everywhere — that is data loss")
    }
}
