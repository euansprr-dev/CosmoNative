import XCTest
@testable import CosmoOS

/// ONE FRONT DOOR + ONE VERB: every capture surface hands the router what it
/// HAS, and the router alone decides what that becomes. These tests pin the
/// resolution ladder — the single most consequential line being that a real
/// link which is not a known platform is a PAGE, which is what turns "paste a
/// sales page" from a dead research row into a decomposable artifact.
@MainActor
final class SwipeIntakeRouterTests: XCTestCase {

    // MARK: - URL ladder

    func testKnownPlatformLinksStayPosts() {
        for url in [
            "https://www.instagram.com/reel/Dalun2ODxrf/",
            "https://www.instagram.com/p/ABC123/",
            "https://youtu.be/NgeyFln7RGk",
            "https://www.youtube.com/watch?v=abc12345678",
            "https://x.com/user/status/1234567890",
            "https://twitter.com/user/status/1234567890",
            "https://www.threads.net/@someone/post/XYZ",
            "https://www.loom.com/share/abc123"
        ] {
            XCTAssertEqual(
                SwipeIntakeRouter.resolve(.url(url)), .postURL(url),
                "\(url) must keep using the existing post pipeline, untouched"
            )
        }
    }

    func testOrdinaryLinksBecomePages() {
        for url in [
            "https://someone.com/sales",
            "https://gumroad.com/l/thing",
            "http://example.co.uk/pricing?ref=x",
            "https://beehiiv.com/p/issue-42"
        ] {
            XCTAssertEqual(
                SwipeIntakeRouter.resolve(.url(url)), .pageFromURL(url),
                "\(url) is a page — the whole point of the kind spine"
            )
        }
    }

    func testLiveBrowserPageAlwaysWinsOverTheURLLadder() {
        // Even an Instagram URL: if you are LOOKING at it in the browser pane,
        // you meant the rendered page, with your session and your scroll.
        XCTAssertEqual(
            SwipeIntakeRouter.resolve(.liveWebPage(url: "https://www.instagram.com/p/ABC/", title: "A post")),
            .pageFromLiveWebPage(url: "https://www.instagram.com/p/ABC/", title: "A post")
        )
    }

    // MARK: - Text

    func testLooseTextBecomesANote() {
        XCTAssertEqual(
            SwipeIntakeRouter.resolve(.text("The best hook I read all week")),
            .note("The best hook I read all week")
        )
    }

    func testTextIsTrimmedBeforeItBecomesANote() {
        XCTAssertEqual(
            SwipeIntakeRouter.resolve(.text("  spaced out  \n")),
            .note("spaced out")
        )
    }

    func testWhitespaceOnlyTextResolvesToNothing() {
        XCTAssertEqual(SwipeIntakeRouter.resolve(.text("   \n  ")), .nothing)
        XCTAssertEqual(SwipeIntakeRouter.resolve(.text("")), .nothing)
    }

    /// A bare pasted link is a link capture even though it arrived as text.
    func testPastedBareLinkTextRoutesThroughTheURLLadder() {
        XCTAssertEqual(
            SwipeIntakeRouter.resolve(.text("https://someone.com/sales")),
            .pageFromURL("https://someone.com/sales")
        )
        XCTAssertEqual(
            SwipeIntakeRouter.resolve(.text("https://www.instagram.com/reel/ABC/")),
            .postURL("https://www.instagram.com/reel/ABC/")
        )
    }

    /// A link buried in prose is a NOTE, not a link capture: the user typed
    /// words around it, so the words are the thing they saved.
    func testLinkWrappedInProseStaysANote() {
        let text = "loved this hook https://someone.com/sales"
        XCTAssertEqual(SwipeIntakeRouter.resolve(.text(text)), .note(text))
    }

    /// A bare domain with no scheme is prose, not a link — high-precision
    /// detection, matching `SwipeURLClassifier.firstURL`'s own contract.
    func testBareDomainIsNotTreatedAsALink() {
        XCTAssertEqual(SwipeIntakeRouter.resolve(.text("example.com")), .note("example.com"))
    }

    // MARK: - Images

    func testImagesBecomeOneFrameSetNotManySwipes() {
        let payloads = (0..<4).map { _ in SwipeImagePayload(data: Data([0x89, 0x50])) }
        XCTAssertEqual(
            SwipeIntakeRouter.resolve(.images(payloads)), .frames(count: 4),
            "four dropped screenshots are ONE artifact — that is what was dragged"
        )
    }

    func testEmptyImageListResolvesToNothing() {
        XCTAssertEqual(SwipeIntakeRouter.resolve(.images([])), .nothing)
    }

    // MARK: - Kind mapping

    func testEveryIntakeReportsItsKind() {
        XCTAssertEqual(SwipeIntakeRouter.Intake.frames(count: 2).kind, .frame)
        XCTAssertEqual(SwipeIntakeRouter.Intake.pageFromURL("x").kind, .page)
        XCTAssertEqual(SwipeIntakeRouter.Intake.pageFromLiveWebPage(url: "x", title: nil).kind, .page)
        XCTAssertEqual(SwipeIntakeRouter.Intake.postURL("x").kind, .post)
        XCTAssertEqual(SwipeIntakeRouter.Intake.note("x").kind, .note)
        XCTAssertNil(SwipeIntakeRouter.Intake.nothing.kind)
    }

    // MARK: - Receipt

    /// The receipt always NAMES what the capture was filed as: the user never
    /// chose it, and a system that silently guesses reads arbitrary the first
    /// time it is wrong. Since the genre spine it speaks GENRE — the kind's
    /// structural fallback when nothing sharper is known ("Screenshot", not
    /// the internal word "Frame"), the seeded/verdict genre when one is.
    func testReceiptNamesTheGenreAndItsUnits() {
        XCTAssertEqual(
            SwipeIntakeReceipt(kind: .page, unitCount: 14, atomUUID: "u").message,
            "Swiped · Page · 14 sections")
        XCTAssertEqual(
            SwipeIntakeReceipt(kind: .frame, unitCount: 3, atomUUID: "u").message,
            "Swiped · Screenshot · 3 images")
        XCTAssertEqual(
            SwipeIntakeReceipt(kind: .frame, unitCount: 1, atomUUID: "u").message,
            "Swiped · Screenshot · 1 image")
        XCTAssertEqual(
            SwipeIntakeReceipt(kind: .page, unitCount: 12, atomUUID: "u", genre: .newsletter).message,
            "Swiped · Newsletter · 12 sections")
    }

    func testReceiptWithNoUnitsStillNamesTheKind() {
        XCTAssertEqual(
            SwipeIntakeReceipt(kind: .post, unitCount: 0, atomUUID: "u").message,
            "Swiped · Post")
    }

    func testFlowReceiptSaysWhereItWent() {
        XCTAssertEqual(
            SwipeIntakeReceipt(kind: .page, unitCount: 8, atomUUID: "u", flowName: "Client X funnel").message,
            "Added to Client X funnel · Page")
    }
}
