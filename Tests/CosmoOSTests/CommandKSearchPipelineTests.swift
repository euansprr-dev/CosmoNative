import Combine
import Observation
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

    func testActionParserParsesBrowserPrefix() {
        let action = CommandKActionParser.parse("BRO")

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

    func testSystemCommandComposerRanksBrowserPrefixFirst() {
        let composer = CommandKSystemCommandComposer()
        let rows = composer.rows(for: "br")

        XCTAssertEqual(rows.first?.action.kind, .openBrowser)
        XCTAssertEqual(rows.first?.title, "Open Browser")
    }

    func testSystemCommandComposerFindsCommandAndDomainPrefixes() {
        let composer = CommandKSystemCommandComposer()

        XCTAssertTrue(composer.rows(for: "co").contains { $0.action.kind == .navigateCommandCenter })
        XCTAssertTrue(composer.rows(for: "co").contains { $0.action.kind == .openCosmoPane })
        XCTAssertTrue(composer.rows(for: "sw").contains { $0.title == "Open Swipe Gallery" && $0.action.kind == .openSwipeGallery })
        XCTAssertTrue(composer.rows(for: "sw").contains { $0.title == "Browse Swipes" && $0.action.kind == .openDomain && $0.action.payload.domain == "swipeGallery" })
        XCTAssertTrue(composer.rows(for: "id").contains { $0.action.kind == .openDomain && $0.action.payload.domain == "ideas" })
    }

    @MainActor
    func testLiveSearchKeepsExistingRailResultsUntilReplacementArrives() async {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        let existing = UnifiedSearchResult(
            id: "atom-existing",
            source: .atoms,
            resultKind: .atom,
            title: "Existing result",
            subtitle: "Idea",
            snippet: "Already visible before the next keystroke",
            icon: "lightbulb.fill",
            accentColor: DS.entityIdea,
            relevance: 0.9,
            atomUUID: "existing-result",
            atomType: .idea,
            thinkspaceId: nil,
            projectUUID: nil,
            projectName: nil,
            thinkspaceNames: [],
            readwiseBookId: nil
        )
        viewModel.cortexMode = .searchResults
        viewModel.isUnifiedSearchActive = true
        viewModel.unifiedGroupedResults = [(.atoms, [existing])]
        viewModel.unifiedFlatResults = [existing]
        viewModel.selectedNodeId = existing.selectionID

        await viewModel.performSearch(query: "unlikely-match-\(UUID().uuidString)")

        XCTAssertEqual(viewModel.unifiedFlatResults.map(\.id), ["atom-existing"])
        XCTAssertEqual(viewModel.selectedNodeId, existing.selectionID)
    }

    @MainActor
    func testBackgroundRefreshForSameQueryKeepsVisibleResultsAndSelection() async {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        let query = "background-refresh-preserve-\(UUID().uuidString)"
        viewModel.cortexMode = .searchResults
        viewModel.query = query
        await viewModel.performSearch(query: query)

        // Simulate the landed search the user is now scrolling: ranked results
        // plus the unified rows built from them, with the second row selected.
        let ranked = [
            RankedResult(
                atomUUID: "preserve-atom-1",
                atomType: .idea,
                title: "Preserve One",
                snippet: "first",
                semanticWeight: 0.9,
                updatedAt: "2026-06-10T00:00:00Z"
            ),
            RankedResult(
                atomUUID: "preserve-atom-2",
                atomType: .idea,
                title: "Preserve Two",
                snippet: "second",
                semanticWeight: 0.8,
                updatedAt: "2026-06-10T00:00:00Z"
            )
        ]
        viewModel.testingApplyUnfilteredResults(ranked)
        let unified = ranked.map { result in
            UnifiedSearchResult(
                id: result.atomUUID,
                source: .atoms,
                resultKind: .atom,
                title: result.title,
                subtitle: "Idea",
                snippet: result.snippet,
                icon: "lightbulb.fill",
                accentColor: DS.entityIdea,
                relevance: result.relevance,
                atomUUID: result.atomUUID,
                atomType: .idea,
                thinkspaceId: nil,
                projectUUID: nil,
                projectName: nil,
                thinkspaceNames: [],
                readwiseBookId: nil
            )
        }
        viewModel.isUnifiedSearchActive = true
        viewModel.unifiedGroupedResults = [(.atoms, unified)]
        viewModel.unifiedFlatResults = unified
        viewModel.selectedNodeId = "preserve-atom-2"
        viewModel.selectedResultIndex = 1

        await viewModel.performSearch(query: query, isBackgroundRefresh: true)

        // The visible list must not be cleared while fresh results are computed,
        // and the user's selection (scroll anchor) must survive the refresh.
        XCTAssertEqual(viewModel.results.map(\.atomUUID), ["preserve-atom-1", "preserve-atom-2"])
        XCTAssertTrue(viewModel.unifiedFlatResults.contains { $0.selectionID == "preserve-atom-2" })
        XCTAssertEqual(viewModel.selectedNodeId, "preserve-atom-2")
        XCTAssertEqual(viewModel.selectedResultIndex, viewModel.searchSelectionIndex(for: "preserve-atom-2"))
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
    func testSwipeQueryShowsCaptureOpenAndBrowseCommandsWithoutDuplicateQuicklink() async throws {
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
        XCTAssertEqual(viewModel.userCommandRows.map(\.title).filter { $0.contains("Swipe") || $0.contains("Swipes") }, [
            "Open Swipe Gallery",
            "Browse Swipes"
        ])
        XCTAssertFalse(viewModel.userCommandRows.contains { $0.title == "Swipe Gallery" })
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
        XCTAssertEqual(result?.title, "Instagram Josh")
        XCTAssertEqual(result?.subtitle, "instagram.com · Browser Favorite")
        XCTAssertEqual(result?.browserURL, URL(string: "https://www.instagram.com/josh")!)
        XCTAssertEqual(result?.browserTitle, "Instagram Josh")
        XCTAssertGreaterThan(result?.relevance ?? 0, 1.0)
    }

    func testUnifiedSearchReturnsMultipleBrowserFavoritesOnSameHost() {
        let pins = [
            CosmoBrowserPinnedSite(
                url: URL(string: "https://www.instagram.com/josh/")!,
                title: "Josh",
                displayName: "Josh"
            ),
            CosmoBrowserPinnedSite(
                url: URL(string: "https://www.instagram.com/euan/")!,
                title: "Euan",
                displayName: "Euan"
            )
        ]

        let output = CommandKUnifiedSearchComposer.buildOutput(
            query: "instagram",
            hybridResults: [],
            swipeGalleryItems: [],
            ideaGalleryItems: [],
            readwiseBooks: [],
            browserPins: pins
        )

        XCTAssertEqual(output.flatResults.filter { $0.source == .browser }.count, 2)
        XCTAssertEqual(Set(output.flatResults.compactMap(\.browserURL)), Set(pins.map(\.url)))
    }

    func testUnifiedSearchFindsRenamedBrowserFavoriteAndPreservesExactURL() {
        let url = URL(string: "https://www.instagram.com/joshvillareal/")!
        let pin = CosmoBrowserPinnedSite(
            url: url,
            title: "Josh Villareal (@joshvillareal)",
            displayName: "Josh Instagram"
        )

        let output = CommandKUnifiedSearchComposer.buildOutput(
            query: "Josh Instagram",
            hybridResults: [],
            swipeGalleryItems: [],
            ideaGalleryItems: [],
            readwiseBooks: [],
            browserPins: [pin]
        )

        let result = output.flatResults.first
        XCTAssertEqual(result?.source, .browser)
        XCTAssertEqual(result?.resultKind, .browserPin)
        XCTAssertEqual(result?.title, "Josh Instagram")
        XCTAssertEqual(result?.browserURL, url)
        XCTAssertEqual(result?.browserTitle, "Josh Instagram")
        XCTAssertGreaterThan(result?.relevance ?? 0, 1.0)
    }

    @MainActor
    func testOpenSelectedRenamedBrowserFavoriteOpensExactBrowserURL() async {
        let url = URL(string: "https://www.instagram.com/joshvillareal/")!
        let result = UnifiedSearchResult(
            id: "browser-pin-josh-instagram",
            source: .browser,
            resultKind: .browserPin,
            title: "Josh Instagram",
            subtitle: "instagram.com · Browser Favorite",
            snippet: url.absoluteString,
            icon: "star.fill",
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
            browserTitle: "Josh Instagram"
        )
        let viewModel = CommandKViewModel()
        let expectation = expectation(description: "renamed browser favorite notification")
        let token = NotificationCenter.default.addObserver(
            forName: CosmoNotification.Navigation.openWebBrowserPane,
            object: nil,
            queue: nil
        ) { notification in
            XCTAssertEqual(notification.userInfo?["url"] as? URL, url)
            XCTAssertEqual(notification.userInfo?["title"] as? String, "Josh Instagram")
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

    @MainActor
    func testSwipeGalleryMostRecentSortUsesParsedDates() async {
        let older = SwipeGalleryItem(
            atomUUID: "swipe-older",
            title: "Older whole second capture",
            createdAt: "2026-05-24T10:00:00Z"
        )
        let newer = SwipeGalleryItem(
            atomUUID: "swipe-newer",
            title: "Newer fractional second capture",
            createdAt: "2026-05-24T10:00:00.999Z"
        )
        let viewModel = CommandKViewModel()
        viewModel.swipeGalleryItems = [older, newer]
        viewModel.swipeSortMode = .recent

        viewModel.recomputeFilteredSwipes()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.cachedFilteredSwipes.map(\.atomUUID), [
            "swipe-newer",
            "swipe-older",
        ])
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
    func testNewSearchQueryResetsActiveSelectionToFirstResult() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CommandKUserCommandStore(fileURL: url, seedBuiltIns: false)
        try await store.saveQuicklink(CommandKQuicklink(
            id: "alpha",
            alias: "alpha",
            title: "Alpha",
            route: .commandKDomain("database"),
            query: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        ))
        try await store.saveQuicklink(CommandKQuicklink(
            id: "alphabet",
            alias: "alphabet",
            title: "Alphabet",
            route: .commandKDomain("ideas"),
            query: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        ))
        let viewModel = CommandKViewModel(userCommandStore: store)
        defer { viewModel.setSurfaceActive(false) }

        viewModel.selectedNodeId = "quicklink-alphabet"
        viewModel.selectedResultIndex = 1

        await viewModel.performSearch(query: "alpha")

        XCTAssertEqual(viewModel.userCommandRows.map(\.id), ["quicklink-alpha", "quicklink-alphabet"])
        XCTAssertEqual(viewModel.selectedResultIndex, 0)
        XCTAssertEqual(viewModel.selectedNodeId, "quicklink-alpha")
    }

    @MainActor
    func testSearchShowsAllMatchingQuicklinksWithoutSystemCommandCap() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CommandKUserCommandStore(fileURL: url, seedBuiltIns: false)
        for index in 1...8 {
            try await store.saveQuicklink(CommandKQuicklink(
                id: "alpha-\(index)",
                alias: "alpha \(index)",
                title: "Alpha \(index)",
                route: .commandKDomain("database"),
                query: nil,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }
        let viewModel = CommandKViewModel(userCommandStore: store)
        defer { viewModel.setSurfaceActive(false) }

        await viewModel.performSearch(query: "alpha")

        XCTAssertEqual(viewModel.userCommandRows.count, 8)
        XCTAssertEqual(Set(viewModel.userCommandRows.map(\.id)).count, 8)
    }

    @MainActor
    func testBrowserPrefixSearchSelectsBrowserCommandFirst() async {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        viewModel.selectedNodeId = "stale-bottom-result"
        viewModel.selectedResultIndex = 9

        await viewModel.performSearch(query: "BRO")

        XCTAssertEqual(viewModel.primaryAction?.kind, .openBrowser)
        XCTAssertEqual(viewModel.selectedResultIndex, 0)
        XCTAssertEqual(viewModel.selectedNodeId, viewModel.primaryAction?.id)
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

    func testMatcherMatchesMultiWordQueriesRegardlessOfOrder() {
        let text = CommandKSearchMatcher.normalize("Turn onboarding calls into a story bank")

        XCTAssertTrue(CommandKSearchMatcher.matches(normalizedQuery: "story onboarding", inNormalizedText: text))
        XCTAssertTrue(CommandKSearchMatcher.matches(normalizedQuery: "bank calls", inNormalizedText: text))
        XCTAssertFalse(CommandKSearchMatcher.matches(normalizedQuery: "story missing", inNormalizedText: text))
    }

    func testMatcherMatchesTokensSpanningMultipleFields() {
        XCTAssertTrue(CommandKSearchMatcher.matches("acme hook", inAny: ["Lead magnet hook", "Notes for Acme client"]))
        XCTAssertFalse(CommandKSearchMatcher.matches("acme missing", inAny: ["Lead magnet hook", "Notes for Acme client"]))
    }

    func testSearchIndexMatchesMultiWordQueriesOutOfOrderAndAcrossFields() {
        var index = CommandKSearchIndex()
        index.replace([
            CommandKSearchIndex.Entry(
                id: "idea-1",
                atomUUID: "idea-1",
                atomType: .idea,
                title: "Greenhouse Ritual",
                snippet: "Daily writing loop",
                updatedAt: "2026-05-01T00:00:00Z"
            )
        ])

        XCTAssertEqual(index.search("ritual greenhouse", limit: 10).map(\.atomUUID), ["idea-1"])
        XCTAssertEqual(index.search("greenhouse writing", limit: 10).map(\.atomUUID), ["idea-1"])
        XCTAssertTrue(index.search("greenhouse missing", limit: 10).isEmpty)
    }

    func testSearchIndexMatchesMetadataContent() {
        var index = CommandKSearchIndex()
        index.replace([
            CommandKSearchIndex.Entry(
                id: "research-1",
                atomUUID: "research-1",
                atomType: .research,
                title: "Untitled capture",
                snippet: nil,
                updatedAt: "2026-05-01T00:00:00Z",
                metadata: "{\"summary\":\"Seller financing playbook\"}"
            )
        ])

        XCTAssertEqual(index.search("seller financing", limit: 10).map(\.atomUUID), ["research-1"])
    }

    func testSearchIndexRanksRecentMatchAboveStaleOnEqualMatchQuality() {
        var index = CommandKSearchIndex()
        index.replace([
            CommandKSearchIndex.Entry(
                id: "stale",
                atomUUID: "stale",
                atomType: .idea,
                title: "Quarterly plan",
                snippet: nil,
                updatedAt: "2020-01-01T00:00:00Z"
            ),
            CommandKSearchIndex.Entry(
                id: "fresh",
                atomUUID: "fresh",
                atomType: .idea,
                title: "Quarterly plan",
                snippet: nil,
                updatedAt: ISO8601.string(from: Date())
            )
        ])

        XCTAssertEqual(index.search("quarterly", limit: 10).map(\.atomUUID), ["fresh", "stale"])
    }

    func testUnifiedSearchIncludesIdeaEngineMatchesWhenGalleryNotLoaded() {
        let ideaMatch = RankedResult(
            atomUUID: "idea-engine-match",
            atomType: .idea,
            title: "Story bank idea",
            snippet: "Turn onboarding calls into a story bank",
            semanticWeight: 0.4,
            structuralWeight: 0.9,
            recencyWeight: 0.5,
            usageWeight: 0.5,
            updatedAt: "2026-05-01T00:00:00Z",
            accessCount: 0
        )

        let output = CommandKUnifiedSearchComposer.buildOutput(
            query: "story bank",
            hybridResults: [ideaMatch],
            swipeGalleryItems: [],
            ideaGalleryItems: [],
            readwiseBooks: [],
            browserPins: []
        )

        let result = output.flatResults.first { $0.atomUUID == "idea-engine-match" }
        XCTAssertEqual(result?.source, .ideas)
        XCTAssertEqual(result?.title, "Story bank idea")
    }

    func testUnifiedSearchRanksSwipesByMatchQualityNotHookScore() {
        let exactMatchLowScore = SwipeGalleryItem(
            atomUUID: "swipe-exact",
            title: "Seller financing playbook",
            hookText: nil,
            hookScore: 1,
            platform: "instagram",
            thumbnailUrl: nil,
            author: nil
        )
        let weakMatchHighScore = SwipeGalleryItem(
            atomUUID: "swipe-weak",
            title: "Unrelated capture",
            hookText: "A seller story about financing a playbook launch",
            hookScore: 99,
            platform: "instagram",
            thumbnailUrl: nil,
            author: nil
        )

        let output = CommandKUnifiedSearchComposer.buildOutput(
            query: "seller financing playbook",
            hybridResults: [],
            swipeGalleryItems: [weakMatchHighScore, exactMatchLowScore],
            ideaGalleryItems: [],
            readwiseBooks: [],
            browserPins: []
        )

        let swipeResults = output.flatResults.filter { $0.source == .swipes }
        XCTAssertEqual(swipeResults.map(\.atomUUID), ["swipe-exact", "swipe-weak"])
    }

    @MainActor
    func testMergeRankedResultsKeepsFreshInstantMatchesMissingFromCache() {
        let cached = RankedResult(
            atomUUID: "cached-atom",
            atomType: .idea,
            title: "Cached idea",
            semanticWeight: 0.6,
            structuralWeight: 0.6,
            recencyWeight: 0.5,
            usageWeight: 0.5,
            updatedAt: "2026-05-01T00:00:00Z"
        )
        let fresh = RankedResult(
            atomUUID: "fresh-atom",
            atomType: .idea,
            title: "Idea created after the cache entry",
            semanticWeight: 0.0,
            structuralWeight: 1.0,
            recencyWeight: 1.0,
            usageWeight: 0.5,
            updatedAt: ISO8601.string(from: Date())
        )
        let duplicateLowerRelevance = RankedResult(
            atomUUID: "cached-atom",
            atomType: .idea,
            title: "Cached idea",
            semanticWeight: 0.0,
            structuralWeight: 0.1,
            recencyWeight: 0.1,
            usageWeight: 0.1,
            updatedAt: "2026-05-01T00:00:00Z"
        )

        let merged = CommandKViewModel.mergeRankedResults(
            primary: [cached],
            additional: [fresh, duplicateLowerRelevance]
        )

        XCTAssertEqual(Set(merged.map(\.atomUUID)), ["cached-atom", "fresh-atom"])
        XCTAssertEqual(merged.filter { $0.atomUUID == "cached-atom" }.count, 1)
        XCTAssertEqual(merged.first { $0.atomUUID == "cached-atom" }?.relevance, cached.relevance)
    }

    func testHybridFTS5QueryRequiresAllTermsAndQuotesTokens() {
        XCTAssertEqual(
            HybridSearchEngine.prepareFTS5Query("seller financing"),
            "\"seller\"* \"financing\"*"
        )
        XCTAssertEqual(
            HybridSearchEngine.prepareFTS5Query("seller financing", matchAnyTerm: true),
            "\"seller\"* OR \"financing\"*"
        )
        // Operators and punctuation must stay inside quotes so MATCH can't throw.
        XCTAssertEqual(
            HybridSearchEngine.prepareFTS5Query("launch (beta) AND done"),
            "\"launch\"* \"(beta)\"* \"AND\"* \"done\"*"
        )
    }

    func testAtomFtsQueryQuotesTokensAndRequiresAllTerms() {
        XCTAssertEqual(
            AtomSearchEngine.prepareFtsQuery("seller financing"),
            "\"seller\"* \"financing\"*"
        )
        XCTAssertEqual(
            AtomSearchEngine.prepareFtsQuery("seller financing", matchAnyTerm: true),
            "\"seller\"* OR \"financing\"*"
        )
        XCTAssertEqual(
            AtomSearchEngine.prepareFtsQuery("launch (beta)"),
            "\"launch\"* \"(beta)\"*"
        )
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

    @MainActor
    func testUnifiedSearchDoesNotPublishForStaleSearchRequest() async {
        let previousBooks = ReadwiseBookStore.shared.books
        ReadwiseBookStore.shared.books = [
            ReadwiseLibraryBook(
                id: 71,
                title: "Awareness",
                author: "Anthony De Mello",
                category: .books,
                coverImageUrl: nil,
                sourceUrl: nil,
                numHighlights: 2,
                highlights: [],
                bookTags: []
            )
        ]
        defer { ReadwiseBookStore.shared.books = previousBooks }

        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        let staleRequestID = await viewModel.testingNextSearchRequestID()
        _ = await viewModel.testingNextSearchRequestID()

        await viewModel.testingUpdateUnifiedSearch(
            query: "awareness",
            searchRequestID: staleRequestID
        )

        XCTAssertTrue(viewModel.unifiedFlatResults.isEmpty)
        XCTAssertFalse(viewModel.isUnifiedSearchActive)
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
            updatedAt: ISO8601.date(from: "2026-05-06T10:00:00Z") ?? Date()
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
        let freshUpdatedAt = ISO8601.string(from: Date())

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

    func testActionParserParsesShorthandClientIdeaCaptureWithColon() {
        let action = CommandKActionParser.parse("idea Euan: turn onboarding calls into a story bank")

        XCTAssertEqual(action?.kind, .createIdea)
        XCTAssertEqual(action?.title, "Create idea for Euan")
        XCTAssertEqual(action?.payload.clientName, "Euan")
        XCTAssertEqual(action?.payload.title, "turn onboarding calls into a story bank")
        XCTAssertEqual(action?.payload.body, "turn onboarding calls into a story bank")
    }

    func testScopedIdeaCaptureIdentityDoesNotChangeWhileDraftChanges() throws {
        let draft = try XCTUnwrap(CommandKActionParser.parse("idea Euan:"))
        let firstWord = try XCTUnwrap(CommandKActionParser.parse("idea Euan: turn"))
        let longerDraft = try XCTUnwrap(CommandKActionParser.parse("idea Euan: turn onboarding calls into a story bank"))
        let otherClient = try XCTUnwrap(CommandKActionParser.parse("idea Ben: turn"))

        XCTAssertEqual(draft.id, firstWord.id)
        XCTAssertEqual(firstWord.id, longerDraft.id)
        XCTAssertNotEqual(firstWord.id, otherClient.id)
    }

    func testActionParserUsesShorthandClientIdeaCaptureAsDraftTargetBeforeColon() {
        let action = CommandKActionParser.parse("idea Euan")

        XCTAssertEqual(action?.kind, .createIdea)
        XCTAssertEqual(action?.title, "Create idea for Euan")
        XCTAssertEqual(action?.payload.clientName, "Euan")
        XCTAssertNil(action?.payload.title)
        XCTAssertFalse(action?.isExecutable ?? true)
        XCTAssertEqual(action?.scopedIdeaPreviewText, "Type the idea after :")
    }

    func testActionParserKeepsIdeaColonAsRegularIdeaCreation() {
        let action = CommandKActionParser.parse("idea: turn onboarding calls into a story bank")

        XCTAssertEqual(action?.kind, .createIdea)
        XCTAssertEqual(action?.title, "Create idea")
        XCTAssertNil(action?.payload.clientName)
        XCTAssertEqual(action?.payload.title, "turn onboarding calls into a story bank")
    }

    func testActionParserDoesNotUseSemicolonForScopedIdeaCapture() {
        let action = CommandKActionParser.parse("idea for Ben; turn onboarding calls into a story bank")

        XCTAssertNil(action)
    }

    @MainActor
    func testScopedIdeaTypingKeepsSelectedPreviewStableAcrossDraftChanges() async throws {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        await viewModel.performSearch(query: "idea Euan:")
        let initialSelection = try XCTUnwrap(viewModel.selectedNodeId)
        XCTAssertEqual(viewModel.primaryAction?.id, initialSelection)

        var selectionDidChange = false
        withObservationTracking {
            _ = viewModel.selectedNodeId
        } onChange: {
            selectionDidChange = true
        }

        await viewModel.performSearch(query: "idea Euan: turn")

        XCTAssertEqual(viewModel.selectedNodeId, initialSelection)
        XCTAssertEqual(viewModel.primaryAction?.id, initialSelection)
        XCTAssertFalse(selectionDidChange)
    }

    @MainActor
    func testSearchPhaseChangesDoNotInvalidateCommandKSurface() async {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        // currentPhase is @ObservationIgnored, so reading it must register no
        // dependency and phase changes must never invalidate the surface.
        var surfaceInvalidated = false
        withObservationTracking {
            _ = viewModel.currentPhase
        } onChange: {
            surfaceInvalidated = true
        }

        viewModel.testingSetSearchPhase(.searching)
        viewModel.testingSetSearchPhase(.instant)
        viewModel.testingSetSearchPhase(.complete)

        XCTAssertFalse(surfaceInvalidated)
        XCTAssertEqual(viewModel.currentPhase, .complete)
    }

    @MainActor
    func testTypingQueryDoesNotInvalidateCommandKSurfaceBeforeSearchPublishes() async {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        // query is @ObservationIgnored, so live typing must register no
        // dependency and must never invalidate the surface.
        var surfaceInvalidated = false
        withObservationTracking {
            _ = viewModel.query
        } onChange: {
            surfaceInvalidated = true
        }

        viewModel.updateQuery("i")
        viewModel.updateQuery("id")
        viewModel.updateQuery("ide")

        XCTAssertEqual(viewModel.query, "ide")
        XCTAssertFalse(surfaceInvalidated)
    }

    @MainActor
    func testClearingQueryDropsVisibleSearchStateImmediately() async {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        await viewModel.performSearch(query: "idea Euan: stable draft")
        XCTAssertEqual(viewModel.primaryAction?.kind, .createIdea)

        viewModel.updateQuery("")

        XCTAssertEqual(viewModel.query, "")
        XCTAssertNil(viewModel.primaryAction)
        XCTAssertTrue(viewModel.userCommandRows.isEmpty)
        XCTAssertTrue(viewModel.unifiedFlatResults.isEmpty)
        XCTAssertEqual(viewModel.currentPhase, .idle)
    }

    func testCommandKPreviewPaneDoesNotForceRemountOnSelectionIdentity() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/CommandK/CortexMasterDetailView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains(".id(subject.selectionIdentity)"))
    }

    func testCommandKViewRoutesKeyboardToActionPanelBeforeRail() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/CommandK/CommandKView.swift"),
            encoding: .utf8
        )

        // Panel presentation lives on the view model so MainView's global escape
        // monitor can peel the panel before closing the whole palette.
        XCTAssertFalse(source.contains("@State private var isActionPanelPresented"))
        XCTAssertTrue(source.contains("if viewModel.isActionPanelPresented {\n            viewModel.isActionPanelPresented = false\n            return .handled\n        }"))
        XCTAssertTrue(source.contains("guard !viewModel.isActionPanelPresented else { return .ignored }"))
        XCTAssertTrue(source.contains("guard !viewModel.isActionPanelPresented else { return }"))
    }

    func testMainViewEscapeMonitorPeelsActionPanelBeforeClosingCommandK() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/MainView.swift"),
            encoding: .utf8
        )

        // The NSEvent monitor consumes Escape before SwiftUI sees it, so the
        // panel-first layering must live there too.
        XCTAssertTrue(source.contains("if commandKViewModel.isActionPanelPresented {\n                        commandKViewModel.isActionPanelPresented = false\n                        return nil\n                    }\n                    closeCommandK()"))
    }

    @MainActor
    func testSearchCompletionKeepsFirstSelectionAndPreviewIdentityStable() async throws {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        await viewModel.performSearch(query: "idea Euan:")
        let initialSelection = try XCTUnwrap(viewModel.selectedNodeId)
        let initialPreviewIdentity = try XCTUnwrap(viewModel.primaryAction?.id)

        var selectionDidChange = false
        withObservationTracking {
            _ = viewModel.selectedNodeId
        } onChange: {
            selectionDidChange = true
        }
        var previewDidChange = false
        withObservationTracking {
            _ = viewModel.primaryAction
        } onChange: {
            previewDidChange = true
        }

        viewModel.testingSetSearchPhase(.searching)
        viewModel.testingSetSearchPhase(.complete)

        XCTAssertEqual(viewModel.selectedNodeId, initialSelection)
        XCTAssertEqual(viewModel.primaryAction?.id, initialPreviewIdentity)
        XCTAssertFalse(selectionDidChange)
        XCTAssertFalse(previewDidChange)
    }

    @MainActor
    func testScopedIdeaDraftChangesDoNotRepublishStablePrimaryAction() async throws {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        await viewModel.performSearch(query: "idea Euan: turn")
        let initialSelection = try XCTUnwrap(viewModel.selectedNodeId)
        let initialAction = try XCTUnwrap(viewModel.primaryAction)

        var previewDidChange = false
        withObservationTracking {
            _ = viewModel.primaryAction
        } onChange: {
            previewDidChange = true
        }

        await viewModel.performSearch(query: "idea Euan: turn onboarding calls into a story bank")

        XCTAssertEqual(viewModel.selectedNodeId, initialSelection)
        XCTAssertEqual(viewModel.primaryAction, initialAction)
        XCTAssertFalse(previewDidChange)
    }

    @MainActor
    func testLegacyRankedResultPassDoesNotStealActiveCommandSelection() async throws {
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
            kind: .openDomain,
            title: "Open Ideas",
            subtitle: "Switch Command-K domain",
            icon: "lightbulb.fill",
            payload: CommandKActionPayload(domain: "ideas", rawText: "ideas")
        )
        let legacyResult = RankedResult(
            atomUUID: "atom-result-that-is-not-the-visible-command",
            atomType: .idea,
            title: "A matching idea",
            snippet: "Legacy ranked results are not the visible top command row",
            semanticWeight: 0.5,
            structuralWeight: 0.5,
            recencyWeight: 0.5,
            usageWeight: 0.5,
            updatedAt: ISO8601.string(from: Date()),
            accessCount: 0
        )

        viewModel.primaryAction = action
        viewModel.selectedNodeId = action.id
        viewModel.selectedResultIndex = 0

        var selectionDidChange = false
        withObservationTracking {
            _ = viewModel.selectedNodeId
        } onChange: {
            selectionDidChange = true
        }

        viewModel.testingApplyUnfilteredResults([legacyResult])

        XCTAssertEqual(viewModel.selectedNodeId, action.id)
        XCTAssertEqual(viewModel.selectedResultIndex, 0)
        XCTAssertFalse(selectionDidChange)
    }

    @MainActor
    func testIdenticalRankedResultPassDoesNotRepublishVisibleResults() {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        let result = RankedResult(
            atomUUID: "stable-result",
            atomType: .idea,
            title: "Stable result",
            snippet: "Same visible result should not republish",
            semanticWeight: 0.5,
            structuralWeight: 0.5,
            recencyWeight: 0.5,
            usageWeight: 0.5,
            updatedAt: "2026-01-01T00:00:00Z",
            accessCount: 0
        )

        var firstApplyDidPublish = false
        withObservationTracking {
            _ = viewModel.results
        } onChange: {
            firstApplyDidPublish = true
        }

        viewModel.testingApplyUnfilteredResults([result])
        XCTAssertTrue(firstApplyDidPublish)

        var secondApplyDidPublish = false
        withObservationTracking {
            _ = viewModel.results
        } onChange: {
            secondApplyDidPublish = true
        }

        viewModel.testingApplyUnfilteredResults([result])
        XCTAssertFalse(secondApplyDidPublish)
        XCTAssertEqual(viewModel.results.map(\.atomUUID), ["stable-result"])
    }

    func testCommandCenterLibraryBrowserUsesSharedISODateParserForLoadedEntities() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/CommandHub/Components/LibraryBrowser.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("ISO8601DateFormatter().date(from:"))
    }

    func testCommandCenterLibraryBrowserCancelsStaleEntityLoads() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/CommandHub/Components/LibraryBrowser.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@State private var loadTask: Task<Void, Never>?"))
        XCTAssertTrue(source.contains("loadTask?.cancel()"))
        XCTAssertTrue(source.contains("latestLoadID"))
        XCTAssertTrue(source.contains("guard latestLoadID == loadID"))
        XCTAssertTrue(source.contains(".onDisappear"))
    }

    func testInboxOverrideSearchCancelsStaleQueriesBeforePublishing() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/Inbox/InboxViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("overrideSearchTask?.cancel()"))
        XCTAssertTrue(source.contains("overrideSearchRequestID"))
        XCTAssertTrue(source.contains("try? await Task.sleep"))
        XCTAssertTrue(source.contains("guard self.overrideSearchRequestID == requestID"))
    }

    func testTaskLinkedAtomPickerDebouncesSearchRequests() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/CommandCenter/TaskLinkedAtomPicker.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@State private var searchTask: Task<Void, Never>?"))
        XCTAssertTrue(source.contains("searchTask?.cancel()"))
        XCTAssertTrue(source.contains("try? await Task.sleep"))
        XCTAssertTrue(source.contains("guard searchRequestID == requestID"))
    }

    func testCommandHubSemanticSearchCancelsStaleQueriesBeforePublishing() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/CommandHub/CommandHubEngine.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private var searchRequestID"))
        XCTAssertTrue(source.contains("searchTask = Task"))
        XCTAssertTrue(source.contains("try? await Task.sleep"))
        XCTAssertTrue(source.contains("guard self.searchRequestID == requestID"))
        XCTAssertFalse(source.contains("Timer.scheduledTimer"))
    }

    func testCanvasDatabasePickerGuardsStaleSearchPublishes() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/CanvasDatabasePicker.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@State private var searchRequestID = UUID()"))
        XCTAssertTrue(source.contains("searchTask?.cancel()"))
        XCTAssertTrue(source.contains("let requestID = UUID()"))
        XCTAssertTrue(source.contains("let query = searchQuery"))
        XCTAssertTrue(source.contains("guard searchRequestID == requestID"))
    }

    func testCortexInformationTableUsesCachedDateFormatters() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/CommandK/CortexInformationTable.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("ISO8601DateFormatter()"))
        XCTAssertFalse(source.contains("DateFormatter()"))
    }

    func testCommandCenterDashboardUsesCachedDisplayDateFormatters() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/CommandCenter/CommandCenterDashboardViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("CosmoDateFormatters.abbreviatedMonthDay"))
        XCTAssertTrue(source.contains("CosmoDateFormatters.abbreviatedWeekdayMonthDay"))
        XCTAssertTrue(source.contains("CosmoDateFormatters.abbreviatedWeekdayFullMonthDay"))
        XCTAssertTrue(source.contains("CosmoDateFormatters.commaYearSuffix"))
        XCTAssertFalse(source.contains("DateFormatter()"))
    }

    func testCommandCenterTaskBucketLoadsReuseTaskViewModelMetadata() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/CommandCenter/CommandCenterDashboardViewModel.swift"),
            encoding: .utf8
        )
        let anytimeBody = try XCTUnwrap(
            source.slice(from: "func loadAnytimeTasks() async", to: "// MARK: - Someday Tasks")
        )
        let somedayBody = try XCTUnwrap(
            source.slice(from: "func loadSomedayTasks() async", to: "// MARK: - Project Tasks")
        )

        XCTAssertTrue(anytimeBody.contains("let state = vm.schedulingState"))
        XCTAssertTrue(anytimeBody.contains("if vm.isRecurring && vm.recurrenceParentUUID == nil"))
        XCTAssertFalse(anytimeBody.contains("metadataValue(as: TaskMetadata.self)"))
        XCTAssertTrue(somedayBody.contains("vm.schedulingState == \"someday\""))
        XCTAssertFalse(somedayBody.contains("metadataValue(as: TaskMetadata.self)"))
    }

    func testCommandCenterAreaLoadingDecodesSortMetadataOncePerArea() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/CommandCenter/CommandCenterDashboardViewModel.swift"),
            encoding: .utf8
        )
        let loadAreasBody = try XCTUnwrap(
            source.slice(from: "func loadAreas() async", to: "func loadProjects() async")
        )

        XCTAssertTrue(loadAreasBody.contains("let areasWithSortOrder"))
        XCTAssertTrue(loadAreasBody.contains("metadataValue(as: AreaMetadata.self)?.sortOrder"))
        XCTAssertTrue(loadAreasBody.contains("areasWithSortOrder.sorted"))
        XCTAssertFalse(loadAreasBody.contains(".sorted {\n                    let a = $0.metadataValue(as: AreaMetadata.self)?.sortOrder"))
    }

    func testContentPolishAnalysisDebouncesAndCancelsDraftChanges() throws {
        let polishSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/Content/ContentPolishView.swift"),
            encoding: .utf8
        )
        let analyzerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("AI/WritingAnalyzer.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(polishSource.contains("@State private var analysisTask: Task<Void, Never>?"))
        XCTAssertTrue(polishSource.contains("@State private var analysisRequestID = UUID()"))
        XCTAssertTrue(polishSource.contains("analysisTask?.cancel()"))
        XCTAssertTrue(polishSource.contains("try? await Task.sleep"))
        XCTAssertTrue(polishSource.contains("Task.detached(priority: .utility)"))
        XCTAssertTrue(polishSource.contains("guard analysisRequestID == requestID"))
        XCTAssertTrue(polishSource.contains(".onDisappear"))
        XCTAssertTrue(analyzerSource.contains("struct WritingAnalysis: Sendable"))
        XCTAssertTrue(analyzerSource.contains("final class WritingAnalyzer: @unchecked Sendable"))
    }

    func testBrainstormContextSidebarSearchCancelsStaleRequestsBeforePublishing() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/Content/BrainstormContextSidebar.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@State private var searchRequestID = UUID()"))
        XCTAssertTrue(source.contains("searchTask?.cancel()"))
        XCTAssertTrue(source.contains("let requestID = UUID()"))
        XCTAssertTrue(source.contains("await performTieredSearch(requestID: requestID)"))
        XCTAssertTrue(source.contains("guard searchRequestID == requestID"))
        XCTAssertTrue(source.contains(".onDisappear"))
    }

    func testBrainstormContextSidebarDetailLoadsCancelStaleRequests() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/Content/BrainstormContextSidebar.swift"),
            encoding: .utf8
        )
        let openDetailBody = try XCTUnwrap(
            source.slice(from: "private func openDetail(atomUUID: String)", to: "private func debounceSearch()")
        )

        XCTAssertTrue(source.contains("@State private var detailLoadTask: Task<Void, Never>?"))
        XCTAssertTrue(source.contains("@State private var detailRequestID = UUID()"))
        XCTAssertTrue(openDetailBody.contains("detailLoadTask?.cancel()"))
        XCTAssertTrue(openDetailBody.contains("let requestID = UUID()"))
        XCTAssertTrue(openDetailBody.contains("guard detailRequestID == requestID"))
        XCTAssertTrue(source.contains("detailLoadTask = nil"))
    }

    func testSwipeStudyCreatorSearchDebouncesAndCachesCreatorFetches() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@State private var creatorSearchTask: Task<Void, Never>?"))
        XCTAssertTrue(source.contains("@State private var creatorSearchRequestID = UUID()"))
        XCTAssertTrue(source.contains("@State private var creatorSearchCache: [CreatorSearchResult] = []"))
        XCTAssertTrue(source.contains("creatorSearchTask?.cancel()"))
        XCTAssertTrue(source.contains("try? await Task.sleep"))
        XCTAssertTrue(source.contains("let cachedItems = creatorSearchCache"))
        XCTAssertTrue(source.contains("guard creatorSearchRequestID == requestID"))
        XCTAssertEqual(source.components(separatedBy: "fetchCreators()").count - 1, 1)
    }

    func testContentFocusPolishHighlightsRunOffMainWithStaleGuard() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@State private var polishAnalysisRequestID = UUID()"))
        XCTAssertTrue(source.contains("polishDebounceTask?.cancel()"))
        XCTAssertTrue(source.contains("let requestID = UUID()"))
        XCTAssertTrue(source.contains("Task.detached(priority: .utility)"))
        XCTAssertTrue(source.contains("WritingAnalyzer.shared.analyze(text: text)"))
        XCTAssertTrue(source.contains("guard polishAnalysisRequestID == requestID"))
        XCTAssertTrue(source.contains("viewModel.state.currentStep.enablesPolishHighlights"))
    }

    func testCreatorListFiltersUseCachedMetadataIndex() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/SwipeStudy/CreatorListView.swift"),
            encoding: .utf8
        )
        let recomputeBody = try XCTUnwrap(
            source.slice(from: "private func recomputeFilteredCreators()", to: "// MARK: - Creator Grid")
        )

        XCTAssertTrue(source.contains("struct CreatorListIndexItem"))
        XCTAssertTrue(source.contains("@State private var creatorIndex: [CreatorListIndexItem] = []"))
        XCTAssertTrue(source.contains("CreatorListFiltering.buildIndex"))
        XCTAssertTrue(source.contains("CreatorListFiltering.filteredCreators"))
        XCTAssertTrue(source.contains("let filteredIDs = CreatorListFiltering.filteredIDs"))
        XCTAssertFalse(recomputeBody.contains("metadataValue(as: CreatorMetadata.self)"))
    }

    func testCreatorProfileSwipeFiltersUseCachedAnalysisIndex() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/SwipeStudy/CreatorProfileView.swift"),
            encoding: .utf8
        )
        let recomputeBody = try XCTUnwrap(
            source.slice(from: "private func recomputeFilteredSwipes()", to: "// MARK: - Swipe Card")
        )

        XCTAssertTrue(source.contains("struct CreatorSwipeIndexItem"))
        XCTAssertTrue(source.contains("@State private var swipeIndex: [CreatorSwipeIndexItem] = []"))
        XCTAssertTrue(source.contains("CreatorProfileSwipeFiltering.buildIndex"))
        XCTAssertTrue(source.contains("CreatorProfileSwipeFiltering.filteredIDs"))
        XCTAssertTrue(source.contains("CreatorProfileSwipeFiltering.filteredSwipes"))
        XCTAssertFalse(recomputeBody.contains("swipeAnalysis"))
    }

    @MainActor
    func testVisibleResultsClearSearchFeedbackImmediately() async {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        viewModel.testingSetSearchFeedback(.empty(query: "missing"))
        await viewModel.performSearch(query: "idea Euan: stable draft")

        XCTAssertEqual(viewModel.searchFeedback, .none)
        XCTAssertEqual(viewModel.primaryAction?.kind, .createIdea)
    }

    @MainActor
    func testSearchFeedbackPublishesEmptyOnlyForCurrentEmptyQuery() async {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        viewModel.query = "unlikely-\(UUID().uuidString)"
        viewModel.testingRefreshSearchFeedback(for: viewModel.query)

        XCTAssertEqual(viewModel.searchFeedback, .empty(query: viewModel.query))

        viewModel.query = "idea Euan: new draft"
        viewModel.testingRefreshSearchFeedback(for: viewModel.query)

        XCTAssertEqual(viewModel.searchFeedback, .none)
    }

    func testCommandKSearchChromeDoesNotExposeLoadingIndicatorForTyping() {
        XCTAssertFalse(CommandKSearchChromePolicy.showsTypingProgressIndicator)
    }

    func testSearchFeedbackEmptyMatchesOnlyCurrentQuery() {
        XCTAssertTrue(CommandKSearchFeedback.empty(query: "alpha").matches(query: " alpha "))
        XCTAssertFalse(CommandKSearchFeedback.empty(query: "alpha").matches(query: "beta"))
        XCTAssertFalse(CommandKSearchFeedback.none.matches(query: "alpha"))
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

    // MARK: - Search Type Exclusion

    func testInternalBookkeepingTypesAreExcludedFromSearch() {
        XCTAssertTrue(AtomType.systemEvent.isExcludedFromSearch, "agent conversation logs are system_event atoms")
        XCTAssertTrue(AtomType.syncEvent.isExcludedFromSearch)
        XCTAssertTrue(AtomType.xpEvent.isExcludedFromSearch)
        XCTAssertTrue(AtomType.dimensionSnapshot.isExcludedFromSearch)
        XCTAssertTrue(AtomType.agentLearning.isExcludedFromSearch)
        XCTAssertTrue(AtomType.userPreference.isExcludedFromSearch)

        XCTAssertFalse(AtomType.idea.isExcludedFromSearch)
        XCTAssertFalse(AtomType.note.isExcludedFromSearch)
        XCTAssertFalse(AtomType.task.isExcludedFromSearch)
        XCTAssertFalse(AtomType.research.isExcludedFromSearch)
        XCTAssertFalse(AtomType.content.isExcludedFromSearch)
        XCTAssertFalse(AtomType.journalEntry.isExcludedFromSearch)

        XCTAssertTrue(AtomType.searchExcludedRawValues.contains("system_event"))
    }

    func testAgentConversationAtomsDoNotSurfaceInHybridSearch() async throws {
        let marker = "zxqvconversationexclusion"
        let conversation = Atom.new(
            type: .systemEvent,
            title: "Agent Conversation: inApp \(marker)",
            body: "[{\"role\":\"user\",\"content\":\"transcript mentioning \(marker)\"}]",
            metadata: "{\"subtype\":\"agent_conversation\"}"
        )
        let idea = Atom.new(
            type: .idea,
            title: "Idea about \(marker)",
            body: "A real idea mentioning \(marker)"
        )
        let savedConversation = try await AtomRepository.shared.create(conversation)
        createdUUIDs.append(savedConversation.uuid)
        let savedIdea = try await AtomRepository.shared.create(idea)
        createdUUIDs.append(savedIdea.uuid)

        let results = try await HybridSearchEngine.shared.search(query: marker, limit: 10)

        XCTAssertFalse(
            results.contains { $0.entityUUID == savedConversation.uuid },
            "system_event atoms must never surface in search results"
        )
        XCTAssertTrue(
            results.contains { $0.entityUUID == savedIdea.uuid },
            "user-facing atoms must still match by keyword"
        )
    }

    private func recentlyUpdated(_ atom: Atom, updatedAt: String) -> Atom {
        var atom = atom
        atom.updatedAt = updatedAt
        return atom
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private extension String {
    func slice(from startMarker: String, to endMarker: String) -> String? {
        guard
            let startRange = range(of: startMarker),
            let endRange = range(of: endMarker, range: startRange.upperBound..<endIndex)
        else {
            return nil
        }

        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}
