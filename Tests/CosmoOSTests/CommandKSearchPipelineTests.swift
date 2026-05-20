import XCTest
@testable import CosmoOS

final class CommandKSearchPipelineTests: XCTestCase {
    private var createdUUIDs: [String] = []

    override func tearDown() async throws {
        let uuids = createdUUIDs.reversed()
        createdUUIDs.removeAll()

        for uuid in uuids {
            try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
        }

        try await super.tearDown()
    }

    func testPlainInstagramURLBecomesSwipeCaptureAction() {
        let action = CommandKActionParser.parse("https://www.instagram.com/reel/ABC123/")

        XCTAssertEqual(action?.kind, .captureSwipe)
        XCTAssertEqual(action?.title, "Capture Swipe")
        XCTAssertEqual(action?.payload.url, "https://www.instagram.com/reel/ABC123/")
    }

    func testPlainWebsiteURLBecomesResearchCaptureAction() {
        let action = CommandKActionParser.parse("https://example.com/article")

        XCTAssertEqual(action?.kind, .captureResearch)
        XCTAssertEqual(action?.title, "Capture Research")
        XCTAssertEqual(action?.payload.url, "https://example.com/article")
    }

    func testActionParserParsesBrowserAlias() {
        let action = CommandKActionParser.parse("browser")

        XCTAssertEqual(action?.kind, .openBrowser)
        XCTAssertEqual(action?.title, "Open Browser")
        XCTAssertNil(action?.payload.url)
    }

    func testActionParserParsesBrowserSearchQuery() {
        let action = CommandKActionParser.parse("browser creator economy research")

        XCTAssertEqual(action?.kind, .openBrowser)
        XCTAssertEqual(action?.payload.queryText, "creator economy research")
    }

    func testActionParserParsesExplicitCosmoSurfaceCommands() {
        let pane = CommandKActionParser.parse("open cosmo pane")
        let floating = CommandKActionParser.parse("ai floating window")

        XCTAssertEqual(pane?.kind, .openCosmoPane)
        XCTAssertEqual(pane?.title, "Open Cosmo as Pane")
        XCTAssertEqual(floating?.kind, .openCosmoWindow)
        XCTAssertEqual(floating?.title, "Open Cosmo Floating Window")
    }

    func testCommandVisualIdentitiesUseSurfaceSpecificIconTiles() {
        let browser = CommandKAction(
            kind: .openBrowser,
            title: "Open Browser",
            subtitle: "Open a persistent research browser pane",
            icon: "globe",
            payload: CommandKActionPayload(rawText: "browser")
        )
        let swipe = CommandKAction(
            kind: .captureSwipe,
            title: "Swipe a link",
            subtitle: "Paste a URL to save it to Swipe Gallery",
            icon: "bolt.fill",
            payload: CommandKActionPayload(rawText: "swipe")
        )
        let cosmo = CommandKAction(
            kind: .openCosmoPane,
            title: "Open Cosmo as Pane",
            subtitle: "Dock the AI assistant beside your workspace",
            icon: "sparkles",
            payload: CommandKActionPayload(rawText: "cosmo")
        )

        XCTAssertEqual(CommandKVisualIdentity.action(browser).style, .browser)
        XCTAssertEqual(CommandKVisualIdentity.action(browser).symbolName, "safari")
        XCTAssertEqual(CommandKVisualIdentity.action(swipe).style, .swipeFile)
        XCTAssertEqual(CommandKVisualIdentity.action(cosmo).style, .cosmo)
    }

    func testSystemCommandComposerDoesNotTreatUnrelatedWordsAsAI() {
        let composer = CommandKSystemCommandComposer()

        XCTAssertEqual(composer.rows(for: "ai").map(\.action.kind), [.openCosmoPane, .openCosmoWindow])
        XCTAssertTrue(composer.rows(for: "main").isEmpty)
    }

    @MainActor
    func testCosmoSearchShowsPaneAndFloatingWindowCommands() async {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        await viewModel.performSearch(query: "cosmo")

        XCTAssertEqual(viewModel.userCommandRows.map(\.title), [
            "Open Cosmo as Pane",
            "Open Cosmo Floating Window"
        ])
        XCTAssertEqual(viewModel.userCommandRows.map(\.action.kind), [
            .openCosmoPane,
            .openCosmoWindow
        ])
    }

    @MainActor
    func testExactCommandQueryKeepsQuicklinksAndUnifiedSearchAvailable() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CommandKUserCommandStore(fileURL: url, seedBuiltIns: false)
        try await store.saveQuicklink(CommandKQuicklink(
            id: "swipes",
            alias: "swipes",
            title: "Swipe Gallery",
            route: .commandKDomain("swipeGallery"),
            query: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        ))
        let viewModel = CommandKViewModel(userCommandStore: store)
        defer { viewModel.setSurfaceActive(false) }

        viewModel.query = "swipe"
        await viewModel.performSearch(query: "swipe")

        XCTAssertEqual(viewModel.primaryAction?.kind, .captureSwipe)
        XCTAssertEqual(viewModel.userCommandRows.map { $0.title }, ["Swipe Gallery"])
        XCTAssertTrue(viewModel.isUnifiedSearchActive)
    }

    @MainActor
    func testOpenSelectedRunsSelectedQuicklinkWhenPrimaryActionIsPresent() async {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }
        let rowAction = CommandKAction(
            kind: .navigateCommandCenter,
            title: "Today",
            subtitle: "Open Command Center",
            icon: "command.circle.fill",
            payload: CommandKActionPayload(quicklinkID: "today", rawText: "today")
        )
        let row = CommandKUserCommandRow(
            id: "quicklink-today",
            title: "Today",
            subtitle: "Quicklink · today",
            icon: "command.circle.fill",
            action: rowAction
        )
        viewModel.primaryAction = CommandKAction(
            kind: .captureSwipe,
            title: "Swipe a link",
            subtitle: "Paste a URL to save it to Swipe Gallery",
            icon: "bolt.fill",
            payload: CommandKActionPayload(rawText: "swipe")
        )
        viewModel.userCommandRows = [row]
        viewModel.selectedNodeId = row.id

        let expectation = expectation(description: "selected quicklink executed")
        let token = NotificationCenter.default.addObserver(
            forName: CosmoNotification.Navigation.navigateToCommandCenter,
            object: nil,
            queue: nil
        ) { _ in expectation.fulfill() }

        viewModel.openSelected()
        await fulfillment(of: [expectation], timeout: 1)
        NotificationCenter.default.removeObserver(token)
    }

    func testUnifiedSearchRanksBrowserPinsByCustomName() {
        let pin = CosmoBrowserPinnedSite(
            id: UUID(uuidString: "9A10AF3C-157C-4BB1-8D41-62A50C7E3F1A")!,
            url: URL(string: "https://www.instagram.com/josh")!,
            title: "Instagram",
            displayName: "Instagram Josh",
            pinnedAt: Date(timeIntervalSince1970: 22)
        )

        let output = CommandKUnifiedSearchComposer.buildOutput(
            query: "Josh",
            hybridResults: [],
            swipeGalleryItems: [],
            ideaGalleryItems: [],
            readwiseBooks: [],
            browserPins: [pin]
        )

        let result = output.flatResults.first
        XCTAssertEqual(result?.source, .browser)
        XCTAssertEqual(result?.resultKind, .browserPin)
        XCTAssertEqual(result?.title, "Open this page in browser")
        XCTAssertEqual(result?.subtitle, "Instagram Josh · instagram.com")
        XCTAssertEqual(result?.browserURL, URL(string: "https://www.instagram.com/josh")!)
        XCTAssertEqual(result?.browserTitle, "Instagram Josh")
        XCTAssertGreaterThan(result?.relevance ?? 0, 1.0)
    }

    @MainActor
    func testOpenSelectedBrowserPinOpensBrowserPane() async {
        let url = URL(string: "https://www.instagram.com/josh")!
        let result = UnifiedSearchResult(
            id: "browser-pin-test",
            source: .browser,
            resultKind: .browserPin,
            title: "Open this page in browser",
            subtitle: "Instagram Josh · instagram.com",
            snippet: url.absoluteString,
            icon: "safari",
            accentColor: DS.entityResearch,
            relevance: 1.4,
            atomUUID: nil,
            atomType: nil,
            thinkspaceId: nil,
            projectUUID: nil,
            projectName: nil,
            thinkspaceNames: [],
            readwiseBookId: nil,
            browserURL: url,
            browserTitle: "Instagram Josh"
        )
        let viewModel = CommandKViewModel()
        let expectation = expectation(description: "browser pane notification")
        let token = NotificationCenter.default.addObserver(
            forName: CosmoNotification.Navigation.openWebBrowserPane,
            object: nil,
            queue: nil
        ) { notification in
            XCTAssertEqual(notification.userInfo?["url"] as? URL, url)
            XCTAssertEqual(notification.userInfo?["title"] as? String, "Instagram Josh")
            expectation.fulfill()
        }

        viewModel.isUnifiedSearchActive = true
        viewModel.unifiedFlatResults = [result]
        viewModel.selectedResultIndex = 0

        viewModel.openSelected()
        await fulfillment(of: [expectation], timeout: 1)
        NotificationCenter.default.removeObserver(token)
    }

    @MainActor
    func testOpenSelectedCosmoPaneCommandPostsPaneNotification() async {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }
        let action = CommandKAction(
            kind: .openCosmoPane,
            title: "Open Cosmo as Pane",
            subtitle: "Dock the AI assistant beside your workspace",
            icon: "sparkles",
            payload: CommandKActionPayload(rawText: "cosmo")
        )
        let row = CommandKUserCommandRow(
            id: "system-cosmo-pane",
            title: action.title,
            subtitle: action.subtitle ?? "",
            icon: action.icon,
            action: action
        )
        viewModel.userCommandRows = [row]
        viewModel.selectedNodeId = row.id

        let expectation = expectation(description: "cosmo pane notification")
        let token = NotificationCenter.default.addObserver(
            forName: CosmoNotification.Navigation.openCosmoWindowPane,
            object: nil,
            queue: nil
        ) { _ in expectation.fulfill() }

        viewModel.openSelected()
        await fulfillment(of: [expectation], timeout: 1)
        NotificationCenter.default.removeObserver(token)
    }

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
    func testIdeaQueryKeepsIdeasQuicklinkAvailableWithOtherSearchOptions() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CommandKUserCommandStore(fileURL: url, seedBuiltIns: false)
        try await store.saveQuicklink(CommandKQuicklink(
            id: "ideas",
            alias: "ideas",
            title: "Ideas",
            route: .commandKDomain("ideas"),
            query: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        ))
        let viewModel = CommandKViewModel(userCommandStore: store)
        defer { viewModel.setSurfaceActive(false) }

        viewModel.query = "idea"
        await viewModel.performSearch(query: "idea")

        XCTAssertEqual(viewModel.cortexMode, .searchResults)
        XCTAssertEqual(viewModel.query, "idea")
        XCTAssertNil(viewModel.primaryAction)
        XCTAssertTrue(viewModel.userCommandRows.contains { $0.title == "Ideas" })
    }

    @MainActor
    func testIdeasQueryKeepsIdeasQuicklinkAvailable() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CommandKUserCommandStore(fileURL: url, seedBuiltIns: false)
        try await store.saveQuicklink(CommandKQuicklink(
            id: "ideas",
            alias: "ideas",
            title: "Ideas",
            route: .commandKDomain("ideas"),
            query: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        ))
        let viewModel = CommandKViewModel(userCommandStore: store)
        defer { viewModel.setSurfaceActive(false) }

        viewModel.query = "ideas"
        await viewModel.performSearch(query: "ideas")

        XCTAssertEqual(viewModel.userCommandRows.map(\.title), ["Ideas"])
        XCTAssertEqual(viewModel.activeCommandAction?.kind, .openDomain)
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

    func testSearchIndexStopsWithoutPublishingPartialResultsWhenCancelled() {
        var index = CommandKSearchIndex()
        index.replace((0..<20).map { offset in
            CommandKSearchIndex.Entry(
                id: "item-\(offset)",
                atomUUID: "item-\(offset)",
                atomType: .idea,
                title: "Laggy Search Item \(offset)",
                snippet: "Command K should abandon stale local scans while the user keeps typing.",
                updatedAt: "2026-05-01T00:00:00Z"
            )
        })

        var probes = 0
        let results = index.search("laggy", limit: 10) {
            probes += 1
            return probes > 3
        }

        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(probes, 4)
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

    func testIdeaRailGroupingSeparatesContentProfilesAndKeepsUnassignedLast() {
        let acmeNew = makeIdea(
            uuid: "idea-acme-new",
            title: "New Acme angle",
            clientName: "Acme",
            clientUUID: "client-acme",
            updatedAt: "2026-05-12T00:00:00Z"
        )
        let zed = makeIdea(
            uuid: "idea-zed",
            title: "Zed angle",
            clientName: "Zed",
            clientUUID: "client-zed",
            updatedAt: "2026-05-11T00:00:00Z"
        )
        let acmeOld = makeIdea(
            uuid: "idea-acme-old",
            title: "Old Acme angle",
            clientName: "Acme",
            clientUUID: "client-acme",
            updatedAt: "2026-05-10T00:00:00Z"
        )
        let unassigned = makeIdea(
            uuid: "idea-unassigned",
            title: "Loose angle",
            clientName: nil,
            clientUUID: nil,
            updatedAt: "2026-05-13T00:00:00Z"
        )

        let sections = CommandKIdeaRailGrouping.sections(from: [zed, unassigned, acmeOld, acmeNew])

        XCTAssertEqual(sections.map(\.title), ["Acme", "Zed", "Unassigned"])
        XCTAssertEqual(sections.map(\.countText), ["2 ideas", "1 idea", "1 idea"])
        XCTAssertEqual(sections[0].items.map(\.atomUUID), ["idea-acme-new", "idea-acme-old"])
        XCTAssertEqual(sections.flatMap { $0.items.map(\.atomUUID) }, [
            "idea-acme-new",
            "idea-acme-old",
            "idea-zed",
            "idea-unassigned"
        ])
    }

    func testRecentComposerUsesOnlyOpenedAtomsForCommandKRecents() {
        let openedAtom = Atom.new(type: .idea, title: "Opened idea")
        let capturedAtom = Atom.new(type: .research, title: "Fresh capture")
        let oldOpenedAt = "2001-05-01T10:00:00Z"
        let freshUpdatedAt = ISO8601DateFormatter().string(from: Date())

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

        XCTAssertEqual(items.map(\.id), [openedAtom.uuid])
        XCTAssertFalse(items.first?.relativeDate.isEmpty ?? true)
        XCTAssertNotEqual(items.first?.relativeDate, "1m")

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

        XCTAssertEqual(ranked.map(\.atomUUID), [openedAtom.uuid])
        XCTAssertEqual(ranked.first?.updatedAt, oldOpenedAt)
    }

    private func makeIdea(
        uuid: String,
        title: String,
        clientName: String?,
        clientUUID: String?,
        updatedAt: String
    ) -> IdeaGalleryItem {
        IdeaGalleryItem(
            id: uuid,
            atomUUID: uuid,
            entityId: 1,
            title: title,
            body: nil,
            status: .spark,
            contentFormat: nil,
            platform: nil,
            clientName: clientName,
            clientUUID: clientUUID,
            tags: [],
            insightScore: nil,
            matchingSwipeCount: nil,
            suggestedFramework: nil,
            isPinned: false,
            contentCount: 0,
            createdAt: "2026-05-09T00:00:00Z",
            updatedAt: updatedAt
        )
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

    func testActionParserParsesScopedIdeaCaptureWithColon() {
        let action = CommandKActionParser.parse("idea for Ben: turn onboarding calls into a story bank")

        XCTAssertEqual(action?.kind, .createIdea)
        XCTAssertEqual(action?.title, "Create idea for Ben")
        XCTAssertEqual(action?.payload.clientName, "Ben")
        XCTAssertEqual(action?.payload.title, "turn onboarding calls into a story bank")
        XCTAssertEqual(action?.payload.body, "turn onboarding calls into a story bank")
    }

    func testActionParserDoesNotUseSemicolonForScopedIdeaCapture() {
        let action = CommandKActionParser.parse("idea for Ben; turn onboarding calls into a story bank")

        XCTAssertNil(action)
    }

    @MainActor
    func testScopedIdeaCaptureIsSelectedAndCarriesDraftPreviewBeforeEnter() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CommandKUserCommandStore(fileURL: url, seedBuiltIns: false)
        try await store.saveQuicklink(CommandKQuicklink(
            id: "ideas",
            alias: "ideas",
            title: "Ideas",
            route: .commandKDomain("ideas"),
            query: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        ))
        let viewModel = CommandKViewModel(userCommandStore: store)
        defer { viewModel.setSurfaceActive(false) }

        let ideaText = "turn onboarding calls into a story bank"
        viewModel.query = "idea for Ben: \(ideaText)"
        await viewModel.performSearch(query: viewModel.query)

        let action = try XCTUnwrap(viewModel.primaryAction)
        XCTAssertEqual(viewModel.selectedNodeId, action.id)
        XCTAssertEqual(action.title, "Create idea for Ben")
        XCTAssertEqual(action.subtitle, "For Ben · \(ideaText)")
        XCTAssertEqual(CortexDetailSubject.action(action).metaLine, "Save to Ben's ideas")
        XCTAssertEqual(CortexDetailSubject.action(action).previewText, ideaText)
    }

    @MainActor
    func testScopedIdeaCaptureCreatesClientIdeaAndOpensIdeasDomain() async throws {
        let uniqueSuffix = UUID().uuidString.prefix(8)
        let clientName = "Ben CommandK \(uniqueSuffix)"
        let ideaText = "Turn onboarding calls into a story bank \(uniqueSuffix)"
        let client = try await AtomRepository.shared.create(type: .clientProfile, title: clientName)
        createdUUIDs.append(client.uuid)

        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        let command = "idea for \(clientName): \(ideaText)"
        viewModel.query = command
        await viewModel.performSearch(query: command)
        XCTAssertEqual(viewModel.primaryAction?.kind, .createIdea)

        viewModel.openSelected()

        var createdIdea: Atom?
        for _ in 0..<20 {
            let ideas = try await AtomRepository.shared.fetchAll(type: .idea)
            if let idea = ideas.first(where: { $0.title == ideaText && $0.ideaClientUUID == client.uuid }) {
                createdIdea = idea
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        for _ in 0..<20 {
            if viewModel.cortexMode == .expandedDomain(.ideas) {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let idea = try XCTUnwrap(createdIdea)
        createdUUIDs.append(idea.uuid)
        XCTAssertEqual(idea.body, ideaText)
        XCTAssertEqual(idea.ideaClientUUID, client.uuid)
        XCTAssertTrue(idea.linksList.contains { $0.linkType == .ideaToClient && $0.uuid == client.uuid })

        let fetchedClient = try await AtomRepository.shared.fetch(uuid: client.uuid)
        let refreshedClient = try XCTUnwrap(fetchedClient)
        XCTAssertTrue(refreshedClient.linksList.contains { $0.linkType == .clientToIdea && $0.uuid == idea.uuid })
        XCTAssertEqual(viewModel.cortexMode, .expandedDomain(.ideas))
        XCTAssertEqual(viewModel.query, "")
        XCTAssertEqual(viewModel.ideaGalleryItems.first?.atomUUID, idea.uuid)
        XCTAssertEqual(viewModel.ideaGalleryItems.first?.clientUUID, client.uuid)
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
