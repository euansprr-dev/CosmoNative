import XCTest
@testable import CosmoOS

/// GUARD of the canvas external-drop ladder. The load-bearing case: an
/// Instagram tile drag carries BOTH the post permalink and its thumbnail
/// image — the permalink must win and become a post swipe. Its mirror: a
/// random image dragged off a webpage also names its source URL, and must
/// KEEP landing as a plain image block. Change the ladder in
/// CanvasExternalDropRouter.decision and these tests together.
final class CanvasExternalDropRouterTests: XCTestCase {

    func testInstagramPermalinkWinsOverRidingThumbnail() {
        XCTAssertEqual(
            CanvasExternalDropRouter.decision(
                webURL: "https://www.instagram.com/p/DAbCdEfGhIj/",
                carriesImage: true
            ),
            .swipeCapture(url: "https://www.instagram.com/p/DAbCdEfGhIj/"),
            "a dragged post tile is the post, not its thumbnail"
        )
    }

    func testUsernamePrefixedPermalinkStillRoutesToSwipe() {
        // The form profile-grid anchors and the address bar actually carry —
        // what the browser pane's drag bridge hands over verbatim.
        for url in [
            "https://www.instagram.com/some.creator/p/DAbCdEfGhIj/",
            "https://www.instagram.com/some.creator/reel/DAbCdEfGhIj/"
        ] {
            XCTAssertEqual(
                CanvasExternalDropRouter.decision(webURL: url, carriesImage: true),
                .swipeCapture(url: url),
                "\(url) must classify as a post, not degrade to a page swipe"
            )
        }
    }

    func testBareLinkBecomesAPageSwipe() {
        XCTAssertEqual(
            CanvasExternalDropRouter.decision(
                webURL: "https://someone.com/sales",
                carriesImage: false
            ),
            .swipeCapture(url: "https://someone.com/sales")
        )
    }

    func testWebImageDragStaysAnImageBlock() {
        // Dragging an image off an ordinary webpage names its source URL —
        // that must not hijack the native image-block pipeline.
        XCTAssertEqual(
            CanvasExternalDropRouter.decision(
                webURL: "https://cdn.example.com/assets/hero.jpg",
                carriesImage: true
            ),
            .imageOrFile
        )
    }

    func testNoWebLinkFallsThroughToImagePipeline() {
        XCTAssertEqual(
            CanvasExternalDropRouter.decision(webURL: nil, carriesImage: true),
            .imageOrFile
        )
        XCTAssertEqual(
            CanvasExternalDropRouter.decision(webURL: nil, carriesImage: false),
            .imageOrFile
        )
    }

    func testNonURLTextNeverCaptures() {
        XCTAssertEqual(
            CanvasExternalDropRouter.decision(webURL: "not a url", carriesImage: false),
            .imageOrFile
        )
    }
}

/// A browser-pane drag reaches AppKit as plain text at best (WebKit keeps
/// page-authored drag types in its private custom-pasteboard format), so the
/// canvas must read URL-shaped text — but ONLY when the text is nothing but
/// the link. Prose that merely contains a URL is not a link drag.
final class CanvasDraggedTextWebLinkTests: XCTestCase {

    func testBareURLTextIsALink() {
        XCTAssertEqual(
            CanvasImageDropController.webLink(inDraggedText: "https://www.instagram.com/benkellyone/p/DbY6CT1iPj9/"),
            "https://www.instagram.com/benkellyone/p/DbY6CT1iPj9/"
        )
    }

    func testSurroundingWhitespaceAndURIListCommentsAreTolerated() {
        XCTAssertEqual(
            CanvasImageDropController.webLink(inDraggedText: "# via drag\nhttps://example.com/page\n"),
            "https://example.com/page"
        )
        XCTAssertEqual(
            CanvasImageDropController.webLink(inDraggedText: "  https://example.com/page  \n"),
            "https://example.com/page"
        )
    }

    func testProseContainingAURLIsNotALinkDrag() {
        XCTAssertNil(CanvasImageDropController.webLink(inDraggedText: "check this https://example.com out"))
        XCTAssertNil(CanvasImageDropController.webLink(inDraggedText: "an ordinary dragged sentence"))
    }

    func testMultipleURLLinesAreNotASingleLinkDrop() {
        XCTAssertNil(CanvasImageDropController.webLink(
            inDraggedText: "https://example.com/a\nhttps://example.com/b"
        ))
    }

    func testNonHTTPSchemesAreRejected() {
        XCTAssertNil(CanvasImageDropController.webLink(inDraggedText: "file:///Users/x/thing.png"))
        XCTAssertNil(CanvasImageDropController.webLink(inDraggedText: "ftp://example.com/a"))
    }
}

/// Freshness ladder of the out-of-band link lane. macOS runs one drag at a
/// time, so an armed session IS the drag being dropped — these pin the two
/// ways it must retire: dragend + grace (a later unrelated drop must never
/// adopt a stale link) and max age (a webview that dies mid-drag never sends
/// dragend at all).
final class BrowserPaneLinkDragSessionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        _ = BrowserPaneLinkDragSession.consume() // clear any leftover state
    }

    func testArmedSessionServesItsURLOnceThenClears() {
        BrowserPaneLinkDragSession.arm(url: "https://www.instagram.com/p/ABC/")
        XCTAssertTrue(BrowserPaneLinkDragSession.isArmed)
        XCTAssertEqual(BrowserPaneLinkDragSession.consume(), "https://www.instagram.com/p/ABC/")
        XCTAssertNil(BrowserPaneLinkDragSession.consume(), "consume must clear — one drop per drag")
    }

    func testDragEndKeepsAShortGraceThenRetires() {
        BrowserPaneLinkDragSession.arm(url: "https://example.com/x")
        BrowserPaneLinkDragSession.noteDragEnded()
        XCTAssertEqual(
            BrowserPaneLinkDragSession.currentURL(now: Date().addingTimeInterval(1)),
            "https://example.com/x",
            "the canvas drop's async loading runs a beat after the page saw dragend"
        )
        XCTAssertNil(
            BrowserPaneLinkDragSession.currentURL(now: Date().addingTimeInterval(10)),
            "past the grace window a drop must never adopt the old link"
        )
    }

    func testMaxAgeRetiresADragThatNeverEnded() {
        BrowserPaneLinkDragSession.arm(url: "https://example.com/x")
        XCTAssertNil(BrowserPaneLinkDragSession.currentURL(now: Date().addingTimeInterval(31)))
    }

    func testReArmingReplacesTheOldDrag() {
        BrowserPaneLinkDragSession.arm(url: "https://example.com/old")
        BrowserPaneLinkDragSession.noteDragEnded()
        BrowserPaneLinkDragSession.arm(url: "https://example.com/new")
        XCTAssertEqual(BrowserPaneLinkDragSession.consume(), "https://example.com/new")
    }
}
