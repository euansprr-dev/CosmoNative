import XCTest
@testable import CosmoOS

final class SwipeIdeaCaptureParserTests: XCTestCase {
    func testParsesNamedIdeaAndClientFromTelegramSwipeCommand() {
        let text = """
        swipe this and link it to an idea for Acme Wealth named: The 3 Silent Taxes Killing Retirement
        https://www.instagram.com/reel/abc123
        """

        let parsed = SwipeIdeaCaptureParser.parse(text)

        XCTAssertEqual(parsed?.url, "https://www.instagram.com/reel/abc123")
        XCTAssertEqual(parsed?.clientName, "Acme Wealth")
        XCTAssertEqual(parsed?.title, "The 3 Silent Taxes Killing Retirement")
    }

    func testParsesQuotedIdeaTitleWithoutClient() {
        let text = """
        swipe this and link it to an idea called "Why Your Team Still Misses Easy Revenue"
        https://youtu.be/example
        """

        let parsed = SwipeIdeaCaptureParser.parse(text)

        XCTAssertEqual(parsed?.url, "https://youtu.be/example")
        XCTAssertNil(parsed?.clientName)
        XCTAssertEqual(parsed?.title, "Why Your Team Still Misses Easy Revenue")
    }

    func testIgnoresPlainSwipeCaptureWithoutIdeaIntent() {
        let text = """
        swipe this
        https://www.instagram.com/reel/plaincapture
        """

        XCTAssertNil(SwipeIdeaCaptureParser.parse(text))
    }
}
