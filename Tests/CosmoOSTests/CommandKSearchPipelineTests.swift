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

        let olderIsCurrent = await pipeline.isCurrent(older)
        let newerIsCurrent = await pipeline.isCurrent(newer)

        XCTAssertFalse(olderIsCurrent)
        XCTAssertTrue(newerIsCurrent)
    }

    func testCommandKCanRepresentContextChunkResult() {
        let source = ContextSource(
            id: "source-1",
            kind: .content,
            title: "Walking Beam brief",
            atomUUID: "content-1",
            bodyHash: "body-hash",
            metadataHash: "meta-hash",
            pinState: .pinned,
            updatedAt: ISO8601DateFormatter().date(from: "2026-05-06T10:00:00Z") ?? Date()
        )
        let chunk = ContextChunk(
            id: "chunk-1",
            sourceID: source.id,
            ordinal: 0,
            rawText: "All bedroom doors need working locks on doors before tenant intake.",
            contextualHeader: "Source: Walking Beam brief.",
            anchor: "chunk-1",
            tokenCount: 20,
            bodyHash: "body-hash"
        )
        let result = ContextRetrievalResult(
            chunk: chunk,
            source: source,
            score: 10.0,
            matchType: "keyword"
        )

        let ranked = CommandKContextChunkAdapter.rankedResult(from: result)

        XCTAssertEqual(ranked.atomUUID, "content-1")
        XCTAssertEqual(ranked.atomType, .content)
        XCTAssertEqual(ranked.title, "Walking Beam brief")
        XCTAssertTrue(ranked.snippet?.contains("locks on doors") == true)
        XCTAssertGreaterThan(ranked.semanticWeight, 0.5)
    }

    func testCommandKDatabaseBrowserUsesGlobalItemsAtHome() {
        let project = LibraryItem(atom: Atom.new(type: .project, title: "Client Project"))
        let standalone = LibraryItem(atom: Atom.new(type: .idea, title: "Loose capture"))
        let nested = LibraryItem(
            atom: Atom.new(type: .content, title: "Nested draft"),
            project: Atom.new(type: .project, title: "Client Project")
        )

        let visibleItems = CommandKDatabaseBrowserDataSource.visibleItems(
            allItems: [project, standalone, nested],
            displayItems: [project],
            recentlyDeletedItems: [],
            isAtHome: true,
            showingRecentlyDeleted: false
        )

        XCTAssertEqual(visibleItems.map(\.title), ["Client Project", "Loose capture", "Nested draft"])
    }

    func testRecentComposerIncludesUpdatedAtomsThatWereNeverOpened() {
        let openedAtom = Atom.new(type: .idea, title: "Opened idea")
        let capturedAtom = Atom.new(type: .research, title: "Fresh capture")
        let oldOpenedAt = "2026-05-01T10:00:00Z"
        let freshUpdatedAt = "2026-05-06T10:00:00Z"

        let items = CommandKRecentComposer.compose(
            opened: [
                CommandKRecentComposer.OpenedAtom(atom: openedAtom, openedAt: oldOpenedAt, accessCount: 3)
            ],
            recentlyUpdated: [
                recentlyUpdated(capturedAtom, updatedAt: freshUpdatedAt),
                recentlyUpdated(openedAtom, updatedAt: oldOpenedAt)
            ],
            limit: 8
        )

        XCTAssertEqual(items.map(\.id), [capturedAtom.uuid, openedAtom.uuid])
        XCTAssertFalse(items.first?.relativeDate.isEmpty ?? true)

        let ranked = CommandKRecentComposer.rankedResults(
            opened: [
                CommandKRecentComposer.OpenedAtom(atom: openedAtom, openedAt: oldOpenedAt, accessCount: 3)
            ],
            recentlyUpdated: [
                recentlyUpdated(capturedAtom, updatedAt: freshUpdatedAt),
                recentlyUpdated(openedAtom, updatedAt: oldOpenedAt)
            ],
            limit: 8
        )

        XCTAssertEqual(ranked.map(\.atomUUID), [capturedAtom.uuid, openedAtom.uuid])
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

    private func recentlyUpdated(_ atom: Atom, updatedAt: String) -> Atom {
        var atom = atom
        atom.updatedAt = updatedAt
        return atom
    }
}
