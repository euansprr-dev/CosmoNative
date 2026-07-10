import XCTest
@testable import CosmoOS

/// The last-mile contract: exports are deterministic, platform-shaped, and
/// never silently lossy.
final class ContentExportFormatterTests: XCTestCase {

    func testShortDraftIsSingleTweet() {
        let sections = ContentExportFormatter.format("One tight thought.", for: .xThread)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].text, "One tight thought.")
        XCTAssertFalse(sections[0].isOverLimit)
    }

    func testLongDraftThreadsWithCountersUnderLimit() {
        let paragraphs = (1...12).map { index in
            "Point \(index): " + String(repeating: "insight ", count: 20)
        }
        let sections = ContentExportFormatter.format(paragraphs.joined(separator: "\n\n"), for: .xThread)

        XCTAssertGreaterThan(sections.count, 1)
        for (offset, section) in sections.enumerated() {
            XCTAssertLessThanOrEqual(section.text.count, ContentExportFormatter.tweetLimit)
            XCTAssertTrue(section.text.hasSuffix("\(offset + 1)/\(sections.count)"),
                          "tweet \(offset) must carry its n/total counter")
        }
        // No content lost: every paragraph's lead word survives somewhere.
        let combined = ContentExportFormatter.combined(sections)
        for index in 1...12 {
            XCTAssertTrue(combined.contains("Point \(index):"), "paragraph \(index) went missing")
        }
    }

    func testGiantParagraphSentencePacksUnderTweetLimit() {
        let giant = String(repeating: "This sentence keeps the thread readable. ", count: 40)
        let sections = ContentExportFormatter.format(giant, for: .xThread)
        XCTAssertGreaterThan(sections.count, 1)
        for section in sections {
            XCTAssertLessThanOrEqual(section.text.count, ContentExportFormatter.tweetLimit)
        }
    }

    func testLinkedInBreaksDenseParagraphsIntoLineBlocks() {
        let dense = String(repeating: "First idea lands here. Second idea follows it. Third idea closes the loop. ", count: 5)
        let sections = ContentExportFormatter.format(dense, for: .linkedIn)
        XCTAssertEqual(sections.count, 1)
        XCTAssertGreaterThan(sections[0].text.components(separatedBy: "\n\n").count, 2,
                             "dense paragraphs must gain feed rhythm")
    }

    func testCarouselSplitsOnSlideMarkers() {
        let draft = """
        SLIDE 1
        Hook line that stops the scroll.

        SLIDE 2
        The tension builds here.

        SLIDE 3
        Payoff and call to action.
        """
        let sections = ContentExportFormatter.format(draft, for: .carouselSlides)
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].label, "Slide 1")
        XCTAssertTrue(sections[0].text.contains("Hook line"))
        XCTAssertFalse(sections[1].text.lowercased().contains("slide"), "markers must not leak into slide text")
    }

    func testCarouselFallsBackToParagraphsWithoutMarkers() {
        let draft = "First slide thought.\n\nSecond slide thought.\n\nThird."
        let sections = ContentExportFormatter.format(draft, for: .carouselSlides)
        XCTAssertEqual(sections.count, 3)
    }

    func testNormalizationCollapsesEditorArtifacts() {
        let messy = "A\n\n\n\n\nB\r\nC   "
        XCTAssertEqual(ContentExportFormatter.normalized(messy), "A\n\nB\nC")
    }

    func testEmptyDraftExportsNothing() {
        XCTAssertTrue(ContentExportFormatter.format("   \n ", for: .xThread).isEmpty)
    }

    func testPerfSnapshotDerivedMetrics() {
        let snapshot = ContentPerfSnapshot(
            id: nil, contentUuid: "c", platform: "instagram",
            views: 10_000, likes: 400, comments: 50, shares: 30, saves: 20,
            followsGained: 12, capturedAt: ISO8601.string(from: Date())
        )
        XCTAssertEqual(snapshot.engagement, 500)
        XCTAssertEqual(snapshot.engagementRate, 0.05, accuracy: 0.0001)
    }
}
