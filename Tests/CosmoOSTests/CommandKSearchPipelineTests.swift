import XCTest
@testable import CosmoOS

final class CommandKSearchPipelineTests: XCTestCase {
    func testSearchIndexNormalizesAndRanksPrefixMatchesFirst() {
        var index = CommandKSearchIndex()
        index.replace([
            CommandKSearchIndex.Entry(
                id: "idea-1",
                atomUUID: "idea-1",
                atomType: .idea,
                title: "Greenhouse Ritual",
                snippet: "Daily writing loop",
                updatedAt: "2026-05-01T00:00:00Z"
            ),
            CommandKSearchIndex.Entry(
                id: "task-1",
                atomUUID: "task-1",
                atomType: .task,
                title: "Review ritual notes",
                snippet: "Greenhouse later in the body",
                updatedAt: "2026-05-01T00:00:00Z"
            )
        ])

        let results = index.search("green", limit: 10)

        XCTAssertEqual(results.map(\.atomUUID), ["idea-1", "task-1"])
        XCTAssertGreaterThan(results[0].structuralWeight, results[1].structuralWeight)
    }

    func testSearchPipelineRejectsStaleRequests() async {
        let pipeline = CommandKSearchPipeline()
        let older = await pipeline.nextRequestID()
        let newer = await pipeline.nextRequestID()

        XCTAssertFalse(await pipeline.isCurrent(older))
        XCTAssertTrue(await pipeline.isCurrent(newer))
    }

    func testActionParserParsesSwipeLinkAction() {
        let action = CommandKActionParser.parse("swipe https://www.instagram.com/p/DWrp-7BiKny/")

        XCTAssertEqual(action?.kind, .captureSwipe)
        XCTAssertEqual(action?.title, "Swipe this link")
        XCTAssertEqual(action?.payload.url, "https://www.instagram.com/p/DWrp-7BiKny/")
    }

    func testActionParserParsesLinkedSwipeIdeaAction() {
        let action = CommandKActionParser.parse("""
        swipe this and link it to an idea for Acme Wealth named: The 3 Silent Taxes Killing Retirement
        https://www.instagram.com/reel/abc123
        """)

        XCTAssertEqual(action?.kind, .captureSwipeWithIdea)
        XCTAssertEqual(action?.payload.url, "https://www.instagram.com/reel/abc123")
        XCTAssertEqual(action?.payload.title, "The 3 Silent Taxes Killing Retirement")
        XCTAssertEqual(action?.payload.clientName, "Acme Wealth")
    }

    func testActionParserParsesCustomCaptureLanePrefix() {
        let action = CommandKActionParser.parse("books/source: quote from chapter 3")

        XCTAssertEqual(action?.kind, .captureLane)
        XCTAssertEqual(action?.title, "Route to books")
        XCTAssertEqual(action?.payload.destinationName, "books")
        XCTAssertEqual(action?.payload.subroute, .source)
        XCTAssertEqual(action?.payload.body, "quote from chapter 3")
    }

    func testActionParserReservedTaskPrefixUsesCreateTaskInsteadOfCaptureLane() {
        let action = CommandKActionParser.parse("task: Review analytics dashboard")

        XCTAssertEqual(action?.kind, .createTask)
        XCTAssertEqual(action?.payload.title, "Review analytics dashboard")
    }

    func testActionParserParsesNavigationAliases() {
        XCTAssertEqual(CommandKActionParser.parse("command center")?.kind, .navigateCommandCenter)
        XCTAssertEqual(CommandKActionParser.parse("canvas")?.kind, .navigateLastThinkspace)
    }

    func testActionParserParsesOpenAppPrefix() {
        let action = CommandKActionParser.parse("open app Safari")

        XCTAssertEqual(action?.kind, .openApp)
        XCTAssertEqual(action?.title, "Open Safari")
        XCTAssertEqual(action?.payload.title, "Safari")
    }
}
