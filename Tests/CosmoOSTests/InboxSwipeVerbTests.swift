import XCTest
@testable import CosmoOS

/// The "File as Swipe" link gate — the same high-precision detection the iPhone
/// engine locks in (kept in lockstep with
/// CosmoOS-iOS/CosmoCoreKit/Tests/InboxTests.swift). A pasted or embedded link
/// qualifies (carrying its exact source text); a plain note or a scheme-less
/// domain does not, so the verb only appears when there's a real link to file.
final class InboxSwipeVerbTests: XCTestCase {

    func testDetectsSwipeLinkAnchor() {
        XCTAssertEqual(
            InboxItem.new(
                source: .quickCapture,
                rawText: "loved this https://youtu.be/abc123 — watch it"
            ).detectedSwipeURL,
            "https://youtu.be/abc123"
        )
        XCTAssertNil(
            InboxItem.new(source: .quickCapture, rawText: "buy miso, eggs, scallions").detectedSwipeURL
        )
        // A bare domain in prose is not a swipe link — a swipe needs a
        // resolvable link, not a guess.
        XCTAssertNil(
            InboxItem.new(source: .quickCapture, rawText: "check example.com sometime").detectedSwipeURL
        )
    }
}
