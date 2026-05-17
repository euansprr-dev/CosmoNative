import XCTest
@testable import CosmoOS

final class CommandKCaptureRouterTests: XCTestCase {
    func testInstagramReelURLResolvesToSwipeCapturePreview() {
        let preview = CommandKCaptureRouter().preview(for: "https://www.instagram.com/reel/ABC123/")

        XCTAssertEqual(preview?.kind, .swipe)
        XCTAssertEqual(preview?.source, .instagram)
        XCTAssertEqual(preview?.primaryAction.title, "Capture Swipe")
        XCTAssertEqual(
            preview?.primaryAction.intent,
            .executeTool(name: "capture_swipe", arguments: ["url": "https://www.instagram.com/reel/ABC123/"])
        )
    }

    func testPlainWebsiteURLResolvesToResearchCapturePreview() {
        let preview = CommandKCaptureRouter().preview(for: "https://example.com/source")

        XCTAssertEqual(preview?.kind, .research)
        XCTAssertEqual(preview?.source, .website)
        XCTAssertEqual(preview?.primaryAction.title, "Capture Research")
        XCTAssertEqual(
            preview?.primaryAction.intent,
            .executeTool(name: "capture_research", arguments: ["url": "https://example.com/source"])
        )
    }

    func testPlainTextResolvesToTaskAndIdeaSuggestions() {
        let previews = CommandKCaptureRouter().suggestions(for: "Review hooks tomorrow")

        XCTAssertTrue(previews.contains { $0.kind == .task })
        XCTAssertTrue(previews.contains { $0.kind == .idea })
    }
}
