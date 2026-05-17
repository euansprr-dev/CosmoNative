import XCTest
@testable import CosmoOS

final class CommandKSearchPipelineTests: XCTestCase {
    func testCommandKLauncherDomainsUsePolishedPresentationLabels() {
        XCTAssertEqual(CommandKTab.allCases.map(\.title), ["Database", "Swipe File", "Ideas", "Library"])
        XCTAssertEqual(CommandKTab.allCases.map(\.searchPlaceholder), [
            "Search database...",
            "Search swipes...",
            "Search ideas...",
            "Search library...",
        ])
    }

    func testCommandKExpandedDomainsDeclarePolishedMastheadAndAdaptiveBodyStyle() {
        XCTAssertTrue(CommandKTab.allCases.allSatisfy { $0.headerArtworkMode == .contentBackedMasthead })
        XCTAssertEqual(CommandKTab.allCases.map(\.headerPersonality), [
            .objectIndex,
            .swipeThumbnails,
            .ideaSnippets,
            .libraryCovers,
        ])
        XCTAssertEqual(CommandKTab.swipeGallery.expandedBodyStyle, .adaptive)
    }

    func testCommandKExpandedHeadersUseContentBackedMastheads() {
        XCTAssertEqual(
            CommandKTab.allCases.map { String(describing: $0.headerArtworkMode) },
            Array(repeating: "contentBackedMasthead", count: CommandKTab.allCases.count)
        )
        XCTAssertEqual(
            CommandKTab.allCases.map { String(describing: $0.headerPersonality) },
            ["objectIndex", "swipeThumbnails", "ideaSnippets", "libraryCovers"]
        )
    }

    func testCommandKHeaderPreviewComposerPrefersRealDomainContent() {
        let recent = RecentDisplayItem(
            id: "recent-1",
            title: "Client Launch Notes",
            type: .note,
            entityId: 1,
            relativeDate: "2h",
            thumbnailURL: nil,
            preview: "Updated acquisition angle."
        )
        let swipe = SwipeGalleryItem(
            atomUUID: "swipe-1",
            title: "Ben Kelly SBA Hook",
            hookText: "Find a $1M business with seller financing",
            hookScore: 8.7,
            platform: "instagram",
            thumbnailUrl: "https://example.com/thumb.jpg",
            author: "Ben Kelly"
        )
        let idea = IdeaGalleryItem(
            id: "idea-1",
            atomUUID: "idea-1",
            entityId: 2,
            title: "Find a home for rent for XYZ",
            body: "Zillow arbitrage outline",
            status: .spark,
            contentFormat: .carousel,
            platform: nil,
            clientName: "Ben A",
            clientUUID: "client-1",
            tags: [],
            insightScore: nil,
            matchingSwipeCount: nil,
            suggestedFramework: nil,
            isPinned: false,
            contentCount: 0,
            createdAt: "2026-05-09T00:00:00Z",
            updatedAt: "2026-05-09T00:00:00Z",
            context: "Rental arbitrage angle",
            hooks: ["How to rent without owning"],
            outline: ["Find market", "Lease rooms"]
        )
        let book = ReadwiseLibraryBook(
            id: 3,
            title: "Awareness",
            author: "Anthony De Mello",
            category: .books,
            coverImageUrl: "https://example.com/cover.jpg",
            sourceUrl: nil,
            numHighlights: 12,
            highlights: [],
            bookTags: []
        )

        let previews = CommandKHeaderPreviewComposer.build(
            recentItems: [recent],
            swipeItems: [swipe],
            ideaItems: [idea],
            readwiseBooks: [book]
        )

        XCTAssertEqual(previews[.database]?.items.first?.title, "Client Launch Notes")
        XCTAssertEqual(previews[.swipeGallery]?.items.first?.thumbnailURL, "https://example.com/thumb.jpg")
        XCTAssertEqual(previews[.ideas]?.items.first?.subtitle, "Ben A")
        XCTAssertEqual(previews[.readwise]?.items.first?.thumbnailURL, "https://example.com/cover.jpg")
    }

    func testCommandKDomainPresentationUsesLightweightCountsWhenDomainContentIsNotLoaded() {
        let presentation = CommandKDomainPresentation.build(
            databaseTotalCount: 42,
            swipeTotalCount: 17,
            ideaTotalCount: 9,
            deepDiveTotalCount: 3,
            recentItems: [],
            swipeItems: [],
            ideaItems: [],
            readwiseBooks: []
        )

        XCTAssertEqual(presentation.counts[.database], 42)
        XCTAssertEqual(presentation.counts[.swipeGallery], 17)
        XCTAssertEqual(presentation.counts[.ideas], 9)
    }

    func testCommandKDomainPresentationPrefersLoadedContentCountsForExpandedDomains() {
        let swipe = SwipeGalleryItem(
            atomUUID: "swipe-1",
            title: "Loaded swipe",
            hookText: nil,
            hookScore: nil,
            platform: "instagram",
            thumbnailUrl: nil,
            author: nil
        )
        let idea = IdeaGalleryItem(
            id: "idea-1",
            atomUUID: "idea-1",
            entityId: 2,
            title: "Loaded idea",
            body: nil,
            status: .spark,
            contentFormat: nil,
            platform: nil,
            clientName: nil,
            clientUUID: nil,
            tags: [],
            insightScore: nil,
            matchingSwipeCount: nil,
            suggestedFramework: nil,
            isPinned: false,
            contentCount: 0,
            createdAt: "2026-05-09T00:00:00Z",
            updatedAt: "2026-05-09T00:00:00Z"
        )

        let presentation = CommandKDomainPresentation.build(
            databaseTotalCount: 42,
            swipeTotalCount: 100,
            ideaTotalCount: 100,
            deepDiveTotalCount: 0,
            recentItems: [],
            swipeItems: [swipe],
            ideaItems: [idea],
            readwiseBooks: []
        )

        XCTAssertEqual(presentation.counts[.swipeGallery], 1)
        XCTAssertEqual(presentation.counts[.ideas], 1)
    }

    func testCommandKSwipeFacetSummaryPrecomputesSidebarAndRailMetrics() {
        let carousel = SwipeGalleryItem(
            atomUUID: "swipe-1",
            title: "Carousel",
            hookText: nil,
            hookScore: 8,
            platform: "instagram",
            thumbnailUrl: nil,
            author: nil,
            primaryNarrative: .storytelling,
            swipeContentFormat: .carousel
        )
        let reel = SwipeGalleryItem(
            atomUUID: "swipe-2",
            title: "Reel",
            hookText: nil,
            hookScore: 6,
            platform: "instagram",
            thumbnailUrl: nil,
            author: nil,
            primaryNarrative: .storytelling,
            swipeContentFormat: .voiceoverReel
        )

        let summary = CommandKSwipeFacetSummary.build(allItems: [carousel, reel], filteredItems: [carousel, reel])

        XCTAssertEqual(summary.topContentFormats.map(\.count), [1, 1])
        XCTAssertEqual(summary.topNarrativeStyles.first?.style, .storytelling)
        XCTAssertEqual(summary.topNarrativeStyles.first?.count, 2)
        XCTAssertEqual(summary.averageHookScore, 7)
    }

    func testCommandKAnimationPolicyLimitsEntranceAnimationsToFirstScreen() {
        XCTAssertNotNil(CommandKAnimationPolicy.entranceAnimation(index: 0))
        XCTAssertNotNil(CommandKAnimationPolicy.entranceAnimation(index: 23))
        XCTAssertNil(CommandKAnimationPolicy.entranceAnimation(index: 24))
    }

    func testIdeasClientLedgerKeepsVerticalScrollWhenColumnsExpand() {
        XCTAssertTrue(CortexIdeasLedgerLayout.clientLedgerOuterScrollAxes.contains(.vertical))
        XCTAssertTrue(CortexIdeasLedgerLayout.clientLedgerInnerScrollAxes.contains(.horizontal))
        XCTAssertFalse(CortexIdeasLedgerLayout.clientLedgerInnerScrollAxes.contains(.vertical))
    }

    func testExpandedDomainTransitionDefersHeavyContentUntilAfterMorphStarts() {
        XCTAssertGreaterThanOrEqual(CommandKDomainTransitionPolicy.browserMountDelay, 0.12)
        XCTAssertGreaterThanOrEqual(CommandKDomainTransitionPolicy.dataHydrationDelay, CommandKDomainTransitionPolicy.browserMountDelay)
        XCTAssertLessThan(CommandKDomainTransitionPolicy.collapseCommitDelay, CommandKDomainTransitionPolicy.browserMountDelay)
    }

    func testCommandKExpandedLayoutKeepsPreviewRailInsideDesktopViewport() {
        XCTAssertEqual(CommandKExpandedLayout.panelHeight(forAvailableHeight: 720), 540)
        XCTAssertEqual(CommandKExpandedLayout.panelHeight(forAvailableHeight: 900), 720)
        XCTAssertEqual(CommandKExpandedLayout.panelHeight(forAvailableHeight: 1_400), 860)
    }

    @MainActor
    func testReturnToCompactClearsExpandedDomainAndQuery() {
        let viewModel = CommandKViewModel()
        viewModel.query = "rent squeeze"
        viewModel.cortexMode = .expandedDomain(.ideas)

        viewModel.returnToCompact()

        XCTAssertEqual(viewModel.cortexMode, .compact)
        XCTAssertEqual(viewModel.query, "")
    }

    @MainActor
    func testSwipeDeletedNotificationPrunesLoadedSwipeGalleryImmediately() async {
        let deleted = SwipeGalleryItem(
            atomUUID: "swipe-deleted",
            title: "Deleted swipe",
            hookText: nil,
            hookScore: nil,
            platform: "instagram",
            thumbnailUrl: nil,
            author: nil
        )
        let kept = SwipeGalleryItem(
            atomUUID: "swipe-kept",
            title: "Kept swipe",
            hookText: nil,
            hookScore: nil,
            platform: "instagram",
            thumbnailUrl: nil,
            author: nil
        )
        let viewModel = CommandKViewModel()
        viewModel.swipeGalleryItems = [deleted, kept]

        NotificationCenter.default.post(
            name: Notification.Name("swipeDeleted"),
            object: nil,
            userInfo: ["uuid": deleted.atomUUID]
        )
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.swipeGalleryItems.map(\.atomUUID), [kept.atomUUID])
    }

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

    func testCommandKDomainRailDataSourceFiltersExpandedDomainItems() {
        let databaseMatch = LibraryItem(atom: Atom.new(type: .content, title: "Client launch note"))
        let databaseMiss = LibraryItem(atom: Atom.new(type: .content, title: "Recipe draft"))
        let swipeMatch = SwipeGalleryItem(
            atomUUID: "swipe-1",
            title: "Lead magnet hook",
            hookText: "A better opening line",
            hookScore: 8,
            platform: "instagram",
            thumbnailUrl: nil,
            author: nil
        )
        let ideaMatch = IdeaGalleryItem(
            id: "idea-1",
            atomUUID: "idea-1",
            entityId: 2,
            title: "Rental arbitrage angle",
            body: "A family office story",
            status: .spark,
            contentFormat: nil,
            platform: nil,
            clientName: "Acme Homes",
            clientUUID: nil,
            tags: ["housing"],
            insightScore: nil,
            matchingSwipeCount: nil,
            suggestedFramework: nil,
            isPinned: false,
            contentCount: 0,
            createdAt: "2026-05-09T00:00:00Z",
            updatedAt: "2026-05-09T00:00:00Z"
        )
        let bookMatch = ReadwiseLibraryBook(
            id: 7,
            title: "Awareness",
            author: "Anthony De Mello",
            category: .books,
            coverImageUrl: nil,
            sourceUrl: nil,
            numHighlights: 4,
            highlights: [],
            bookTags: []
        )

        XCTAssertEqual(
            CommandKDomainRailDataSource.items(
                for: .database,
                query: "client",
                databaseItems: [databaseMatch, databaseMiss],
                swipeItems: [swipeMatch],
                ideaItems: [ideaMatch],
                readwiseBooks: [bookMatch]
            ).map(\.title),
            ["Client launch note"]
        )
        XCTAssertEqual(
            CommandKDomainRailDataSource.items(
                for: .swipeGallery,
                query: "hook",
                databaseItems: [databaseMatch],
                swipeItems: [swipeMatch],
                ideaItems: [ideaMatch],
                readwiseBooks: [bookMatch]
            ).map(\.selectionID),
            ["swipe-1"]
        )
        XCTAssertEqual(
            CommandKDomainRailDataSource.items(
                for: .ideas,
                query: "rental",
                databaseItems: [databaseMatch],
                swipeItems: [swipeMatch],
                ideaItems: [ideaMatch],
                readwiseBooks: [bookMatch]
            ).map(\.selectionID),
            ["idea-1"]
        )
        XCTAssertEqual(
            CommandKDomainRailDataSource.items(
                for: .readwise,
                query: "awareness",
                databaseItems: [databaseMatch],
                swipeItems: [swipeMatch],
                ideaItems: [ideaMatch],
                readwiseBooks: [bookMatch]
            ).map(\.selectionID),
            ["readwise-7"]
        )
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
