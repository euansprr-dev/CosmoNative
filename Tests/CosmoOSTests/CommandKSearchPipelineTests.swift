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

    // A pasted URL always offers BOTH capture verbs: the source type picks
    // the default row, never the set of options (July 23 2026).
    func testSwipeSourceURLOffersResearchCaptureAsAlternate() {
        let primary = CommandKActionParser.parse("https://youtube.com/watch?v=dQw4w9WgXcQ")
        let alternate = CommandKActionParser.alternateAction(for: primary)

        XCTAssertEqual(primary?.kind, .captureSwipe)
        XCTAssertEqual(alternate?.kind, .captureResearch)
        XCTAssertEqual(alternate?.payload.url, "https://youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertTrue(alternate?.isExecutable ?? false)
    }

    func testResearchURLOffersSwipeCaptureAsAlternate() {
        let primary = CommandKActionParser.parse("https://example.com/article")
        let alternate = CommandKActionParser.alternateAction(for: primary)

        XCTAssertEqual(primary?.kind, .captureResearch)
        XCTAssertEqual(alternate?.kind, .captureSwipe)
        XCTAssertEqual(alternate?.payload.url, "https://example.com/article")
    }

    func testNonURLActionsHaveNoAlternateCapture() {
        XCTAssertNil(CommandKActionParser.alternateAction(for: CommandKActionParser.parse("task buy filters")))
        XCTAssertNil(CommandKActionParser.alternateAction(for: CommandKActionParser.parse("browser")))
        XCTAssertNil(CommandKActionParser.alternateAction(for: nil))
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
        // Custom-name matches score 1.0 inside a title tier so pins win ties
        // against atoms without jumping tiers.
        XCTAssertEqual(result?.lexicalTier, .titleMatch)
        XCTAssertEqual(result?.relevance, 1.0)
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
        XCTAssertEqual(result?.lexicalTier, .exactTitle)
        XCTAssertEqual(result?.relevance, 1.0)
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
    func testOpenSelectedBrowserFavoriteDismissesCommandKBeforeOpeningBrowserPane() async {
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
        var events: [Notification.Name] = []
        let expectation = expectation(description: "browser favorite opened")
        let closeToken = NotificationCenter.default.addObserver(
            forName: CosmoNotification.NodeGraph.closeCommandK,
            object: nil,
            queue: nil
        ) { notification in
            events.append(notification.name)
        }
        let openToken = NotificationCenter.default.addObserver(
            forName: CosmoNotification.Navigation.openWebBrowserPane,
            object: nil,
            queue: nil
        ) { notification in
            events.append(notification.name)
            expectation.fulfill()
        }

        viewModel.isUnifiedSearchActive = true
        viewModel.unifiedFlatResults = [result]
        viewModel.selectedResultIndex = 0

        viewModel.openSelected()
        await fulfillment(of: [expectation], timeout: 1)
        NotificationCenter.default.removeObserver(closeToken)
        NotificationCenter.default.removeObserver(openToken)

        XCTAssertEqual(
            events,
            [
                CosmoNotification.NodeGraph.closeCommandK,
                CosmoNotification.Navigation.openWebBrowserPane
            ]
        )
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
            "Search database…",
            "Search swipes…",
            "Search ideas…",
            "Search library…",
        ])
    }

    func testCommandKExpandedDomainsDeclarePolishedMastheadAndAdaptiveBodyStyle() {
        XCTAssertTrue(CommandKTab.allCases.allSatisfy { $0.headerArtworkMode == .contentBackedMasthead })
        XCTAssertEqual(CommandKTab.swipeGallery.expandedBodyStyle, .adaptive)
    }

    func testCommandKExpandedHeadersUseContentBackedMastheads() {
        XCTAssertEqual(
            CommandKTab.allCases.map { String(describing: $0.headerArtworkMode) },
            Array(repeating: "contentBackedMasthead", count: CommandKTab.allCases.count)
        )
    }

    func testCommandKDomainPresentationUsesLightweightCountsWhenDomainContentIsNotLoaded() {
        let presentation = CommandKDomainPresentation.build(
            databaseTotalCount: 42,
            swipeTotalCount: 17,
            ideaTotalCount: 9,
            deepDiveTotalCount: 3,
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
        // Bare "idea" now leads with the composer action — and the ideas
        // destination still rides alongside it, as exactly ONE row (the
        // system command wins; the same-target quicklink yields to it).
        XCTAssertEqual(viewModel.primaryAction?.kind, .createIdea)
        let ideasRows = viewModel.userCommandRows.filter {
            $0.action.navigationTargetKey == "domain|ideas"
        }
        XCTAssertEqual(ideasRows.map(\.title), ["Open Ideas"])
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

        // "ideas" parses to the Open Ideas primary action; the system row
        // and the same-target quicklink both yield to it — one destination,
        // one row.
        XCTAssertTrue(viewModel.userCommandRows.allSatisfy {
            $0.action.navigationTargetKey != "domain|ideas"
        })
        XCTAssertEqual(viewModel.activeCommandAction?.kind, .openDomain)
        XCTAssertEqual(viewModel.activeCommandAction?.payload.domain, "ideas")
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
        // Distinct destinations (unique saved searches) — the navigation-
        // target dedupe must never cap these.
        for index in 1...8 {
            try await store.saveQuicklink(CommandKQuicklink(
                id: "alpha-\(index)",
                alias: "alpha \(index)",
                title: "Alpha \(index)",
                route: .savedSearch("alpha topic \(index)"),
                query: "alpha topic \(index)",
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

    // MARK: - Lexical tier invariants

    func testLexicalMatchTierLadder() {
        func match(_ query: String, title: String, extra: String? = nil) -> (tier: LexicalTier, quality: Double) {
            CommandKSearchMatcher.lexicalMatch(
                normalizedQuery: CommandKSearchMatcher.normalizeQuery(query),
                normalizedTitle: CommandKSearchMatcher.normalize(title),
                normalizedFullText: CommandKSearchMatcher.searchableText(from: [title, extra])
            )
        }

        XCTAssertEqual(match("seller financing", title: "Seller Financing").tier, .exactTitle)
        XCTAssertEqual(match("seller", title: "Seller financing playbook").tier, .titlePrefix)
        XCTAssertEqual(match("financing", title: "Seller financing playbook").tier, .titleMatch)
        XCTAssertEqual(match("playbook seller", title: "Seller financing playbook").tier, .titleMatch)
        XCTAssertEqual(
            match("mortgage", title: "Seller financing", extra: "mortgage rates commentary").tier,
            .keywordInBody
        )

        let none = match("quantum", title: "Seller financing", extra: "mortgage rates")
        XCTAssertEqual(none.tier, .semanticOnly)
        XCTAssertEqual(none.quality, 0)
    }

    func testExactTitleMatchOutranksHigherSemanticScore() {
        let exact = RankedResult(
            atomUUID: "exact",
            atomType: .idea,
            title: "Greenhouse ritual",
            semanticWeight: 0.0,
            structuralWeight: 1.0,
            recencyWeight: 0.2,
            usageWeight: 0.5,
            lexicalTier: .exactTitle,
            updatedAt: "2026-01-01T00:00:00Z"
        )
        let fuzzy = RankedResult(
            atomUUID: "fuzzy",
            atomType: .research,
            title: "Morning routines reel",
            semanticWeight: 0.95,
            structuralWeight: 0.0,
            recencyWeight: 1.0,
            usageWeight: 0.5,
            lexicalTier: .semanticOnly,
            updatedAt: ISO8601.string(from: Date())
        )

        // The blended score still favors the fuzzy semantic match — the tier
        // is what puts the exact keyword match first.
        XCTAssertGreaterThan(fuzzy.relevance, exact.relevance)
        XCTAssertEqual([fuzzy, exact].sorted().map(\.atomUUID), ["exact", "fuzzy"])
    }

    func testSemanticOnlyQueryOrdersBySemanticScore() {
        let results = [0.3, 0.9, 0.6].enumerated().map { index, semantic in
            RankedResult(
                atomUUID: "semantic-\(index)",
                atomType: .idea,
                title: "Result \(index)",
                semanticWeight: semantic,
                structuralWeight: 0.0,
                recencyWeight: 0.5,
                usageWeight: 0.5,
                lexicalTier: .semanticOnly,
                updatedAt: "2026-05-01T00:00:00Z"
            )
        }

        // Natural-language recall: with no keyword evidence anywhere, ordering
        // is purely the blended semantic score.
        XCTAssertEqual(results.sorted().map(\.atomUUID), ["semantic-1", "semantic-2", "semantic-0"])
    }

    func testHybridMapperAssignsTitleTiersAndBM25BodyTier() {
        func searchResult(
            title: String,
            bm25: Double,
            matchedAllTerms: Bool
        ) -> HybridSearchEngine.SearchResult {
            HybridSearchEngine.SearchResult(
                entityType: .idea,
                entityId: 1,
                entityUUID: "uuid",
                title: title,
                preview: "",
                bm25Score: bm25,
                vectorSimilarity: 0.4,
                combinedScore: 0.4,
                matchReason: .keywordMatch,
                updatedAt: "2026-05-01T00:00:00Z",
                matchedAllTerms: matchedAllTerms
            )
        }
        let query = CommandKSearchMatcher.normalizeQuery("greenhouse ritual")

        XCTAssertEqual(
            CommandKHybridResultMapper.lexicalTier(
                for: searchResult(title: "Greenhouse ritual", bm25: 8, matchedAllTerms: true),
                normalizedQuery: query
            ),
            .exactTitle
        )
        // Strict BM25 hit whose keywords live in the body beyond the preview.
        XCTAssertEqual(
            CommandKHybridResultMapper.lexicalTier(
                for: searchResult(title: "Weekly notes", bm25: 6, matchedAllTerms: true),
                normalizedQuery: query
            ),
            .keywordInBody
        )
        // Broad any-term partials carry no full keyword evidence.
        XCTAssertEqual(
            CommandKHybridResultMapper.lexicalTier(
                for: searchResult(title: "Greenhouse only", bm25: 4, matchedAllTerms: false),
                normalizedQuery: query
            ),
            .semanticOnly
        )
        // Pure-vector results can carry a chunk field name as title — never
        // award title tiers without keyword evidence.
        XCTAssertEqual(
            CommandKHybridResultMapper.lexicalTier(
                for: searchResult(title: "Greenhouse ritual", bm25: 0, matchedAllTerms: false),
                normalizedQuery: query
            ),
            .semanticOnly
        )
    }

    @MainActor
    func testMergeRankedResultsPrefersBetterTierForSameAtom() {
        let hybridSemantic = RankedResult(
            atomUUID: "atom-1",
            atomType: .idea,
            title: "Greenhouse ritual",
            semanticWeight: 0.9,
            structuralWeight: 0.1,
            recencyWeight: 1.0,
            usageWeight: 0.5,
            lexicalTier: .semanticOnly,
            updatedAt: "2026-05-01T00:00:00Z"
        )
        let instantExact = RankedResult(
            atomUUID: "atom-1",
            atomType: .idea,
            title: "Greenhouse ritual",
            semanticWeight: 0.0,
            structuralWeight: 1.0,
            recencyWeight: 0.2,
            usageWeight: 0.5,
            lexicalTier: .exactTitle,
            updatedAt: "2026-05-01T00:00:00Z"
        )

        let merged = CommandKViewModel.mergeRankedResults(
            primary: [hybridSemantic],
            additional: [instantExact]
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.lexicalTier, .exactTitle)
    }

    func testComposerOrdersGroupsByTierBeforeRelevance() {
        // A title-prefix atom with modest blended relevance…
        let titleMatchAtom = RankedResult(
            atomUUID: "atom-title",
            atomType: .content,
            title: "Greenhouse ritual",
            semanticWeight: 0.1,
            structuralWeight: 0.88,
            recencyWeight: 0.3,
            usageWeight: 0.5,
            lexicalTier: .titlePrefix,
            updatedAt: "2026-01-01T00:00:00Z"
        )
        // …versus a semantically-similar swipe with a much higher score.
        let fuzzySwipeHybrid = RankedResult(
            atomUUID: "swipe-fuzzy",
            atomType: .research,
            title: "Morning light reel",
            semanticWeight: 0.9,
            structuralWeight: 0.0,
            recencyWeight: 1.0,
            usageWeight: 0.5,
            lexicalTier: .semanticOnly,
            updatedAt: ISO8601.string(from: Date())
        )
        let fuzzySwipeItem = SwipeGalleryItem(
            atomUUID: "swipe-fuzzy",
            title: "Morning light reel",
            hookText: nil,
            hookScore: 90,
            platform: "instagram",
            thumbnailUrl: nil,
            author: nil
        )

        let output = CommandKUnifiedSearchComposer.buildOutput(
            query: "greenhouse",
            hybridResults: [fuzzySwipeHybrid, titleMatchAtom],
            swipeGalleryItems: [fuzzySwipeItem],
            ideaGalleryItems: [],
            readwiseBooks: [],
            browserPins: []
        )

        // The atoms group leads because its best result has keyword evidence —
        // one fuzzy semantic swipe cannot lift the swipes section above it.
        XCTAssertEqual(output.groupedResults.first?.source, .atoms)
        XCTAssertEqual(output.flatResults.first?.atomUUID, "atom-title")
        XCTAssertGreaterThan(
            fuzzySwipeHybrid.relevance,
            titleMatchAtom.relevance,
            "regression guard: the old relevance-only ordering would have put the swipe first"
        )
    }

    func testIdeaFieldMatchFloorStaysWithinKeywordTier() {
        let bodyMatchIdea = IdeaGalleryItem(
            id: "idea-body",
            atomUUID: "idea-body",
            entityId: 3,
            title: "Studio revamp",
            body: "Notes about the greenhouse build",
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
        let titleMatchAtom = RankedResult(
            atomUUID: "atom-title",
            atomType: .content,
            title: "Greenhouse ritual",
            semanticWeight: 0.05,
            structuralWeight: 0.88,
            recencyWeight: 0.2,
            usageWeight: 0.5,
            lexicalTier: .titlePrefix,
            updatedAt: "2026-01-01T00:00:00Z"
        )

        let output = CommandKUnifiedSearchComposer.buildOutput(
            query: "greenhouse",
            hybridResults: [titleMatchAtom],
            swipeGalleryItems: [],
            ideaGalleryItems: [bodyMatchIdea],
            readwiseBooks: [],
            browserPins: []
        )

        let ideaResult = output.flatResults.first { $0.atomUUID == "idea-body" }
        XCTAssertEqual(ideaResult?.lexicalTier, .keywordInBody)
        XCTAssertEqual(output.groupedResults.first?.source, .atoms)
        XCTAssertEqual(output.flatResults.first?.atomUUID, "atom-title")
    }

    func testSwipesSectionRanksBelowDatabaseOnEqualTier() {
        // Database atom and swipe both carry title-level keyword evidence,
        // but the swipe scores higher on blended relevance…
        let databaseAtom = RankedResult(
            atomUUID: "atom-db",
            atomType: .content,
            title: "Notes on the greenhouse ritual",
            semanticWeight: 0.1,
            structuralWeight: 0.64,
            recencyWeight: 0.3,
            usageWeight: 0.5,
            lexicalTier: .titleMatch,
            updatedAt: "2026-01-01T00:00:00Z"
        )
        let strongSwipe = SwipeGalleryItem(
            atomUUID: "swipe-strong",
            title: "The greenhouse ritual reel",
            hookText: nil,
            hookScore: 90,
            platform: "instagram",
            thumbnailUrl: nil,
            author: nil
        )

        let output = CommandKUnifiedSearchComposer.buildOutput(
            query: "greenhouse ritual",
            hybridResults: [databaseAtom],
            swipeGalleryItems: [strongSwipe],
            ideaGalleryItems: [],
            readwiseBooks: [],
            browserPins: []
        )

        // …yet on equal tier the database section leads: someone matching
        // their own atoms is looking for those, not the swipe file.
        XCTAssertEqual(output.groupedResults.map(\.source), [.atoms, .swipes])
        XCTAssertEqual(output.flatResults.first?.atomUUID, "atom-db")
        let swipeResult = output.flatResults.first { $0.atomUUID == "swipe-strong" }
        XCTAssertEqual(swipeResult?.lexicalTier, .titleMatch)
        XCTAssertGreaterThan(
            swipeResult?.relevance ?? 0,
            databaseAtom.relevance,
            "regression guard: relevance-only section ordering would have put swipes first"
        )
    }

    func testSwipesSectionLeadsWhenStrictlyBetterTier() {
        // The swipe's title IS the query; the database only has a body match.
        let exactSwipe = SwipeGalleryItem(
            atomUUID: "swipe-exact",
            title: "Greenhouse ritual",
            hookText: nil,
            hookScore: 10,
            platform: "instagram",
            thumbnailUrl: nil,
            author: nil
        )
        let bodyMatchAtom = RankedResult(
            atomUUID: "atom-body",
            atomType: .content,
            title: "Weekly planning notes",
            semanticWeight: 0.4,
            structuralWeight: 0.42,
            recencyWeight: 1.0,
            usageWeight: 0.5,
            lexicalTier: .keywordInBody,
            updatedAt: ISO8601.string(from: Date())
        )

        let output = CommandKUnifiedSearchComposer.buildOutput(
            query: "greenhouse ritual",
            hybridResults: [bodyMatchAtom],
            swipeGalleryItems: [exactSwipe],
            ideaGalleryItems: [],
            readwiseBooks: [],
            browserPins: []
        )

        XCTAssertEqual(output.groupedResults.map(\.source), [.swipes, .atoms])
        XCTAssertEqual(output.flatResults.first?.atomUUID, "swipe-exact")
    }

    // MARK: - Result order lock (Spotlight contract)

    private func stableOrderRow(
        _ id: String,
        source: UnifiedSearchSource = .atoms,
        snippet: String? = nil,
        relevance: Double = 0.5,
        tier: LexicalTier = .titleMatch
    ) -> UnifiedSearchResult {
        UnifiedSearchResult(
            id: id,
            source: source,
            resultKind: .atom,
            title: id,
            subtitle: nil,
            snippet: snippet,
            icon: "lightbulb.fill",
            accentColor: DS.entityIdea,
            relevance: relevance,
            lexicalTier: tier,
            atomUUID: id,
            atomType: .idea,
            thinkspaceId: nil,
            projectUUID: nil,
            projectName: nil,
            thinkspaceNames: [],
            readwiseBookId: nil
        )
    }

    func testStabilizeOrderKeepsVisibleRowsPinnedAndAppendsNewcomers() {
        let visible: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])] = [
            (.atoms, [stableOrderRow("atom-a"), stableOrderRow("atom-b")])
        ]
        // The late wave ranks a newcomer first and inverts a/b — none of
        // that may move rows the user is already reading.
        let incoming: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])] = [
            (.atoms, [
                stableOrderRow("atom-new", relevance: 1.0, tier: .exactTitle),
                stableOrderRow("atom-b", relevance: 0.9),
                stableOrderRow("atom-a", relevance: 0.4)
            ])
        ]

        let stabilized = CommandKUnifiedSearchComposer.stabilizeOrder(visible: visible, incoming: incoming)

        XCTAssertEqual(
            stabilized.first?.results.map(\.id),
            ["atom-a", "atom-b", "atom-new"],
            "visible rows keep their positions; newcomers append below"
        )
    }

    func testStabilizeOrderKeepsSectionOrderAndAppendsNewSections() {
        let visible: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])] = [
            (.atoms, [stableOrderRow("atom-a")]),
            (.swipes, [stableOrderRow("swipe-a", source: .swipes)])
        ]
        let incoming: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])] = [
            (.swipes, [stableOrderRow("swipe-a", source: .swipes, relevance: 1.0, tier: .exactTitle)]),
            (.atoms, [stableOrderRow("atom-a")]),
            (.ideas, [stableOrderRow("idea-a", source: .ideas)])
        ]

        let stabilized = CommandKUnifiedSearchComposer.stabilizeOrder(visible: visible, incoming: incoming)

        XCTAssertEqual(
            stabilized.map(\.source),
            [.atoms, .swipes, .ideas],
            "visible sections keep their order; new sections append at the end"
        )
    }

    func testStabilizeOrderRefreshesContentAndDropsVanishedRows() {
        let visible: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])] = [
            (.atoms, [
                stableOrderRow("atom-a", snippet: "stale snippet"),
                stableOrderRow("atom-gone")
            ])
        ]
        let incoming: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])] = [
            (.atoms, [stableOrderRow("atom-a", snippet: "enriched snippet", relevance: 0.8)])
        ]

        let stabilized = CommandKUnifiedSearchComposer.stabilizeOrder(visible: visible, incoming: incoming)

        let rows = stabilized.first?.results ?? []
        XCTAssertEqual(rows.map(\.id), ["atom-a"], "rows absent from the fresh wave drop out")
        XCTAssertEqual(rows.first?.snippet, "enriched snippet", "position is pinned but content refreshes")
        XCTAssertEqual(rows.first?.relevance, 0.8)
    }

    @MainActor
    func testLateWaveCannotReorderSettledResultsOrMoveSelection() async {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        // First wave lands while the settle window is open: free ranking.
        viewModel.testingApplyUnfilteredResults([
            RankedResult(
                atomUUID: "settled-one",
                atomType: .idea,
                title: "Settled One",
                snippet: "first",
                semanticWeight: 0.9,
                lexicalTier: .titleMatch,
                updatedAt: "2026-06-10T00:00:00Z"
            ),
            RankedResult(
                atomUUID: "settled-two",
                atomType: .idea,
                title: "Settled Two",
                snippet: "second",
                semanticWeight: 0.8,
                lexicalTier: .titleMatch,
                updatedAt: "2026-06-10T00:00:00Z"
            )
        ])
        let firstRequest = await viewModel.testingNextSearchRequestID()
        await viewModel.testingUpdateUnifiedSearch(query: "settled", searchRequestID: firstRequest)
        XCTAssertEqual(
            viewModel.unifiedFlatResults.map(\.atomUUID),
            ["settled-one", "settled-two"]
        )

        // The user has been reading the list and arrowed to the second row.
        viewModel.selectedNodeId = "settled-two"
        viewModel.selectedResultIndex = viewModel.searchSelectionIndex(for: "settled-two")
        viewModel.testingCloseResultOrderSettleWindow()

        // A late wave (AI-style boost) inverts the ranking and adds a
        // newcomer that would rank first.
        viewModel.testingApplyUnfilteredResults([
            RankedResult(
                atomUUID: "settled-newcomer",
                atomType: .idea,
                title: "Settled Newcomer",
                snippet: "new exact hit",
                semanticWeight: 1.0,
                lexicalTier: .exactTitle,
                updatedAt: "2026-06-10T00:00:00Z"
            ),
            RankedResult(
                atomUUID: "settled-two",
                atomType: .idea,
                title: "Settled Two",
                snippet: "second",
                semanticWeight: 0.95,
                lexicalTier: .titleMatch,
                updatedAt: "2026-06-10T00:00:00Z"
            ),
            RankedResult(
                atomUUID: "settled-one",
                atomType: .idea,
                title: "Settled One",
                snippet: "first",
                semanticWeight: 0.4,
                lexicalTier: .titleMatch,
                updatedAt: "2026-06-10T00:00:00Z"
            )
        ])
        let lateRequest = await viewModel.testingNextSearchRequestID()
        await viewModel.testingUpdateUnifiedSearchAsLateWave(query: "settled", searchRequestID: lateRequest)

        // Order is frozen: the rows the user was reading stay put and the
        // newcomer appends below; the highlighted row never moves.
        XCTAssertEqual(
            viewModel.unifiedFlatResults.map(\.atomUUID),
            ["settled-one", "settled-two", "settled-newcomer"]
        )
        XCTAssertEqual(viewModel.selectedNodeId, "settled-two")
        XCTAssertEqual(
            viewModel.selectedResultIndex,
            viewModel.searchSelectionIndex(for: "settled-two")
        )
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
        // Ideas is find-and-jump: hits lead, then the board jump row trails
        // so ⏎ still opens the top hit while the board stays one row away.
        XCTAssertEqual(
            CommandKDomainRailDataSource.items(
                for: .ideas,
                query: "rental",
                databaseItems: [databaseMatch],
                swipeItems: [swipeMatch],
                ideaItems: [ideaMatch],
                readwiseBooks: [bookMatch]
            ).map(\.selectionID),
            ["idea-1", "ideas-board-jump-search"]
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

    // MARK: - Composer creation grammar

    func testBareCreationKeywordsMapToComposerShapes() {
        XCTAssertEqual(CommandKActionParser.parse("idea")?.kind, .createIdea)
        XCTAssertEqual(CommandKActionParser.parse("task")?.kind, .createTask)
        XCTAssertEqual(CommandKActionParser.parse("note")?.kind, .createNote)
        XCTAssertEqual(CommandKActionParser.parse("page")?.kind, .createNote)
        XCTAssertEqual(CommandKActionParser.parse("content")?.kind, .createContent)
        XCTAssertEqual(CommandKActionParser.parse("capture")?.kind, .captureInbox)
        XCTAssertEqual(CommandKActionParser.parse("inbox")?.kind, .captureInbox)
        XCTAssertEqual(CommandKActionParser.parse("swipe")?.kind, .captureSwipe)

        // Empty creates are not executable — Enter drops into the composer.
        XCTAssertEqual(CommandKActionParser.parse("idea")?.isExecutable, false)
        XCTAssertEqual(CommandKActionParser.parse("task")?.isExecutable, false)
    }

    func testBareCreationRespectsWordBoundaries() {
        XCTAssertNotEqual(CommandKActionParser.parse("ideation")?.kind, .createIdea)
        XCTAssertNotEqual(CommandKActionParser.parse("noteworthy findings")?.kind, .createNote)
        XCTAssertNotEqual(CommandKActionParser.parse("pagespeed findings")?.kind, .createNote)
    }

    func testTaskTrailingTextPrefillsComposerTitle() {
        let action = CommandKActionParser.parse("task buy water filters")
        XCTAssertEqual(action?.kind, .createTask)
        XCTAssertEqual(action?.payload.title, "buy water filters")
        XCTAssertEqual(action?.isExecutable, true)
    }

    func testCaptureTrailingTextPrefillsBody() {
        let action = CommandKActionParser.parse("capture the thing about pacing")
        XCTAssertEqual(action?.kind, .captureInbox)
        XCTAssertEqual(action?.payload.body, "the thing about pacing")
    }

    func testBareIdeaWithTrailingTextStaysScopedClientCapture() {
        // "idea <text>" is the scoped client-draft grammar, not a title prefill.
        let action = CommandKActionParser.parse("idea Euan")
        XCTAssertEqual(action?.kind, .createIdea)
        XCTAssertEqual(action?.payload.clientName, "Euan")
    }

    func testNewVerbFormsResolveShapesWithPrefill() {
        let note = CommandKActionParser.parse("new note morning pages")
        XCTAssertEqual(note?.kind, .createNote)
        XCTAssertEqual(note?.payload.title, "morning pages")

        let page = CommandKActionParser.parse("new page morning pages")
        XCTAssertEqual(page?.kind, note?.kind)
        XCTAssertEqual(page?.payload.title, note?.payload.title)

        // The explicit verb is unambiguous, so idea prefill is allowed here.
        let idea = CommandKActionParser.parse("new idea morning hooks")
        XCTAssertEqual(idea?.kind, .createIdea)
        XCTAssertEqual(idea?.payload.title, "morning hooks")

        XCTAssertEqual(CommandKActionParser.parse("create task ship it")?.kind, .createTask)
    }

    func testUrlQueriesBypassBareCreationGrammar() {
        let action = CommandKActionParser.parse("swipe https://www.instagram.com/reel/abc123/")
        XCTAssertEqual(action?.kind, .captureSwipe)
        XCTAssertNotNil(action?.payload.url)
    }

    func testNewKeywordListsAllCreationShapesInOrbFanOrder() {
        let rows = CommandKSystemCommandComposer().rows(for: "new")
        let creationTitles = rows.filter { $0.subtitle.contains("Create") }.map(\.title)
        XCTAssertEqual(
            creationTitles,
            ["New Task", "New Page", "New Idea", "New Capture", "New Content", "New Swipe", "New Space",
             "New Group", "New Book", "New Course"]
        )
    }

    func testNewPrefixNarrowsCreationShapes() {
        let rows = CommandKSystemCommandComposer().rows(for: "new id")
        XCTAssertEqual(rows.map(\.title), ["New Idea"])
    }

    func testComposerDraftMapsCreationActionsOnly() {
        let create = CommandKActionParser.parse("task")!
        XCTAssertEqual(CommandKComposerDraft.draft(for: create)?.kind, .createTask)

        let browse = CommandKActionParser.parse("browser")!
        XCTAssertNil(CommandKComposerDraft.draft(for: browse))
    }

    func testComposerDraftCarriesPrefillsAndSyncsQueryText() {
        let action = CommandKActionParser.parse("task buy water filters")!
        var draft = CommandKComposerDraft.draft(for: action)!
        XCTAssertEqual(draft.form.value(for: .title), "buy water filters")

        // Query keeps syncing into the lead field…
        let retyped = CommandKActionParser.parse("task buy better water filters")!
        draft.syncPrefills(from: retyped)
        XCTAssertEqual(draft.form.value(for: .title), "buy better water filters")

        // …until the user edits it by hand.
        draft.titleEditedManually = true
        draft.form.setValue("Replace the filters", for: .title)
        let retypedAgain = CommandKActionParser.parse("task something else")!
        draft.syncPrefills(from: retypedAgain)
        XCTAssertEqual(draft.form.value(for: .title), "Replace the filters")
    }

    func testScopedIdeaActionPrefillsComposerBrand() {
        let action = CommandKActionParser.parse("idea Euan: story bank")!
        let draft = CommandKComposerDraft.draft(for: action)
        XCTAssertEqual(draft?.kind, .createIdea)
        XCTAssertEqual(draft?.form.value(for: .client), "Euan")
        XCTAssertEqual(draft?.form.value(for: .title), "story bank")
    }

    func testCommandKViewRoutesEscapeToComposerBeforeActionPanel() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/CommandK/CommandKView.swift"),
            encoding: .utf8
        )
        let composerPeel = source.range(of: "if viewModel.isComposerFocused {\n            viewModel.isComposerFocused = false\n            return .handled\n        }")
        let panelPeel = source.range(of: "if viewModel.isActionPanelPresented {\n            viewModel.isActionPanelPresented = false\n            return .handled\n        }")
        let peel = try XCTUnwrap(composerPeel)
        let panel = try XCTUnwrap(panelPeel)
        XCTAssertTrue(peel.lowerBound < panel.lowerBound, "composer focus must peel before the actions panel")
    }

    func testMainViewEscapeMonitorPeelsComposerBeforeActionPanel() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/MainView.swift"),
            encoding: .utf8
        )
        let composerPeel = source.range(of: "if commandKViewModel.isComposerFocused {\n                        commandKViewModel.isComposerFocused = false\n                        return nil\n                    }")
        let panelPeel = source.range(of: "if commandKViewModel.isActionPanelPresented {\n                        commandKViewModel.isActionPanelPresented = false\n                        return nil\n                    }")
        let peel = try XCTUnwrap(composerPeel)
        let panel = try XCTUnwrap(panelPeel)
        XCTAssertTrue(peel.lowerBound < panel.lowerBound, "composer focus must peel before the actions panel in the NSEvent monitor")
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

    /// The complement of the test above. `query` staying untracked is what
    /// keeps typing cheap — but the expanded domain rail (Swipe File and
    /// friends) filters locally and returns early out of `performSearch`, so
    /// it needs a tracked signal or its cached rows never refresh and the
    /// list ignores what you type. `domainFilterQuery` is that signal.
    @MainActor
    func testTypingPublishesTrackedDomainFilterQueryForExpandedDomainScopes() async {
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }

        var railInvalidated = false
        withObservationTracking {
            _ = viewModel.domainFilterQuery
        } onChange: {
            railInvalidated = true
        }

        viewModel.updateQuery("foreclosures")

        XCTAssertTrue(
            railInvalidated,
            "domainFilterQuery must be observation-tracked — the domain rail's onChange key rides it"
        )
        XCTAssertEqual(viewModel.domainFilterQuery, viewModel.query)
    }

    /// Guard the read site itself: `domainItemsKey` and the filter compute in
    /// CortexMasterDetailView must never reach for `viewModel.query`. That
    /// read is invisible to SwiftUI, and the whole surface is built from just
    /// (viewModel, isDomainHydrated) — so the body never re-runs on a
    /// keystroke and the Swipe File list silently stays unfiltered.
    func testDomainRailFilterReadsTheTrackedQueryMirror() throws {
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("UI/CommandK/CortexMasterDetailView.swift"),
            encoding: .utf8
        )

        let key = try XCTUnwrap(
            source.slice(from: "private var domainItemsKey: String {", to: "\n    }"),
            "domainItemsKey moved — re-anchor this guard"
        )
        XCTAssertTrue(key.contains("viewModel.domainFilterQuery"))
        XCTAssertFalse(key.contains("viewModel.query"))

        let compute = try XCTUnwrap(
            source.slice(from: "private func computeDomainItems()", to: "\n    }"),
            "computeDomainItems moved — re-anchor this guard"
        )
        XCTAssertTrue(compute.contains("query: viewModel.domainFilterQuery"))
        XCTAssertFalse(compute.contains("query: viewModel.query"))
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

        // Set the query through the public path first — clearing only takes
        // effect when the view model knows a non-empty query is on screen —
        // then run the search directly so the test stays deterministic.
        viewModel.updateQuery("idea Euan: stable draft")
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
            source.slice(from: "func loadAnytimeTasks(", to: "// MARK: - Someday Tasks")
        )
        let somedayBody = try XCTUnwrap(
            source.slice(from: "func loadSomedayTasks(", to: "// MARK: - Project Tasks")
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

    func testAskCortexGrammarParsesQuestionPrefix() {
        // `?<question>` claims the query before navigation aliases can.
        let action = CommandKActionParser.parse( "?what did I learn about hooks")
        XCTAssertEqual(action?.kind, .askCortex)
        XCTAssertEqual(action?.payload.body, "what did I learn about hooks")

        let aliased = CommandKActionParser.parse( "recall: swipe structures for storytelling")
        XCTAssertEqual(aliased?.kind, .askCortex)
        XCTAssertEqual(aliased?.payload.body, "swipe structures for storytelling")

        // A bare "?" has no question — no action row.
        XCTAssertNil(CommandKActionParser.parse( "?"))
        // Plain queries keep their existing parse.
        XCTAssertNotEqual(CommandKActionParser.parse( "home")?.kind, .askCortex)
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
        // Creator search moved from SwipeStudyFocusModeView into the details
        // section during the Swipe Study V2 rebuild — the debounce/caching
        // contract rides with it.
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/SwipeStudy/SwipeStudyDetailsSection.swift"),
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

    // MARK: - Matched-context excerpts (Phase 1)

    func testMatchExcerptCentersOnDeepBodyMatch() {
        let filler = String(repeating: "Opening filler paragraph about greenhouse mornings. ", count: 20)
        let sentence = "The compounding advantage comes from writing every single day."
        let body = filler + sentence + " Trailing thoughts continue here."

        let excerpt = CommandKMatchExcerpt.excerpt(from: body, query: "compounding advantage")

        XCTAssertNotNil(excerpt)
        XCTAssertTrue(excerpt!.contains("compounding advantage"))
        XCTAssertTrue(excerpt!.hasPrefix("…"), "a mid-document window must mark its cut leading edge")
        XCTAssertLessThanOrEqual(excerpt!.count, CommandKMatchExcerpt.maxLength + 2)
    }

    func testMatchExcerptPrefersPhraseOverEarlierLoneToken() {
        let body = "Advantage is mentioned early on. "
            + String(repeating: "Unrelated middle text. ", count: 30)
            + "But the compounding advantage appears here as a phrase."

        let excerpt = CommandKMatchExcerpt.excerpt(from: body, query: "compounding advantage")

        XCTAssertTrue(
            excerpt?.contains("compounding advantage") == true,
            "the full phrase anchors the window, not the first lone token"
        )
    }

    func testMatchExcerptNilWhenNothingMatches() {
        XCTAssertNil(CommandKMatchExcerpt.excerpt(from: "Completely unrelated text", query: "zxqvmissing"))
        XCTAssertNil(CommandKMatchExcerpt.excerpt(from: nil, query: "anything"))
        XCTAssertNil(CommandKMatchExcerpt.excerpt(from: "Some body", query: "   "))
    }

    func testMatchExcerptCollapsesNewlinesToOneLine() {
        let body = "First line of the note\nsecond line with the target sentence inside\nthird line"
        let excerpt = CommandKMatchExcerpt.excerpt(from: body, query: "target sentence")

        XCTAssertNotNil(excerpt)
        XCTAssertFalse(excerpt!.contains("\n"), "row excerpts must read as a single line")
    }

    func testHighlighterMatchesPhraseFirstThenTokensAndMergesOverlaps() {
        let phraseRanges = CommandKMatchHighlighter.matchRanges(
            of: "quick brown",
            in: "The quick brown fox and another quick brown pair"
        )
        XCTAssertEqual(phraseRanges.count, 2, "whole-phrase occurrences win over per-token confetti")

        let tokenRanges = CommandKMatchHighlighter.matchRanges(
            of: "search searching",
            in: "searching for search"
        )
        // "searching" contains "search" — overlapping token hits must merge.
        XCTAssertEqual(tokenRanges.count, 2)
    }

    func testHighlighterIsCaseAndDiacriticInsensitive() {
        let ranges = CommandKMatchHighlighter.matchRanges(of: "cafe", in: "The Café was open")
        XCTAssertEqual(ranges.count, 1)
    }

    func testReadingWindowCentersDeepMatchAndSkipsHeadMatches() {
        let filler = String(repeating: "Filler sentence for the reading window test. ", count: 40)
        let body = filler + "Here lives the matched passage about compounding advantage." + filler

        let window = CommandKMatchExcerpt.readingWindow(
            anchoredBy: "…the matched passage about compounding advantage…",
            query: "compounding advantage",
            in: body
        )
        XCTAssertNotNil(window)
        XCTAssertTrue(window!.contains("compounding advantage"))
        XCTAssertTrue(window!.hasPrefix("…"))

        // A match near the head needs no window — the head already shows it.
        XCTAssertNil(CommandKMatchExcerpt.readingWindow(
            anchoredBy: nil,
            query: "filler sentence",
            in: body
        ))
    }

    @MainActor
    func testInstantIndexBodyMatchCarriesExcerptAndTitleMatchDoesNot() {
        let deepBody = String(repeating: "Padding paragraph before the payload. ", count: 10)
            + "The exact sentence I remember writing lives here."
        var index = CommandKSearchIndex()
        index.replace([
            CommandKSearchIndex.Entry(
                id: "body-hit",
                atomUUID: "body-hit",
                atomType: .note,
                title: "Weekly reflections",
                snippet: deepBody,
                updatedAt: "2026-07-01T00:00:00Z"
            ),
            CommandKSearchIndex.Entry(
                id: "title-hit",
                atomUUID: "title-hit",
                atomType: .note,
                title: "Exact sentence collection",
                snippet: "Body without the query phrase at all",
                updatedAt: "2026-07-01T00:00:00Z"
            )
        ])

        let results = index.search("exact sentence", limit: 10)
        let bodyHit = results.first { $0.atomUUID == "body-hit" }
        let titleHit = results.first { $0.atomUUID == "title-hit" }

        XCTAssertEqual(
            bodyHit?.lexicalTier, .phraseInBody,
            "a contiguous phrase in the body is stronger evidence than scattered keywords"
        )
        XCTAssertTrue(
            bodyHit?.matchedExcerpt?.contains("exact sentence I remember writing") == true,
            "body matches must carry the matched sentence, not the body head"
        )
        XCTAssertNil(titleHit?.matchedExcerpt, "title matches keep their clean subtitle")
    }

    func testHybridMapperPropagatesMatchedExcerpt() {
        let result = HybridSearchEngine.SearchResult(
            entityType: .note,
            entityId: 1,
            entityUUID: "uuid-excerpt",
            title: "Weekly notes",
            preview: "preview head",
            bm25Score: 6,
            vectorSimilarity: 0.2,
            combinedScore: 0.4,
            matchReason: .keywordMatch,
            updatedAt: "2026-07-01T00:00:00Z",
            matchedAllTerms: true,
            matchedExcerpt: "…the matched sentence in context…"
        )
        let ranked = CommandKHybridResultMapper.rankedResult(
            from: result,
            atomType: .note,
            normalizedQuery: CommandKSearchMatcher.normalizeQuery("matched sentence")
        )
        XCTAssertEqual(ranked.matchedExcerpt, "…the matched sentence in context…")
    }

    func testHybridSearchReturnsBodySnippetForDeepSentenceMatch() async throws {
        let marker = "zxqvsnippetdeepmatch"
        let filler = String(repeating: "Ordinary journal filler with no special terms. ", count: 30)
        let atom = Atom.new(
            type: .note,
            title: "Long note with a buried sentence",
            body: filler + "The buried sentence mentions \(marker) exactly once here. " + filler
        )
        let saved = try await AtomRepository.shared.create(atom)
        createdUUIDs.append(saved.uuid)

        let results = try await HybridSearchEngine.shared.search(query: marker, limit: 10)
        let hit = results.first { $0.entityUUID == saved.uuid }

        XCTAssertNotNil(hit, "the buried sentence must be findable by keyword")
        XCTAssertTrue(
            hit?.matchedExcerpt?.contains(marker) == true,
            "keyword hits must carry an FTS5 snippet centered on the match"
        )
        XCTAssertFalse(
            hit?.matchedExcerpt?.contains("\u{E000}") == true,
            "snippet markers must be stripped before the excerpt leaves the engine"
        )
    }

    func testHybridSearchTitleOnlyMatchHasNoBodyExcerpt() async throws {
        let marker = "zxqvtitleonlymatch"
        let atom = Atom.new(
            type: .note,
            title: "Note titled \(marker)",
            body: "Body text that never mentions the special term."
        )
        let saved = try await AtomRepository.shared.create(atom)
        createdUUIDs.append(saved.uuid)

        let results = try await HybridSearchEngine.shared.search(query: marker, limit: 10)
        let hit = results.first { $0.entityUUID == saved.uuid }

        XCTAssertNotNil(hit)
        XCTAssertNil(
            hit?.matchedExcerpt,
            "a title-only match must not present the body head as match evidence"
        )
    }

    // MARK: - Phrase + proximity retrieval ladder (Phase 2)

    func testPhraseInBodyRanksAboveScatteredKeywords() {
        let scattered = RankedResult(
            atomUUID: "scattered",
            atomType: .note,
            title: "Weekly notes",
            semanticWeight: 0.9,
            structuralWeight: 0.9,
            recencyWeight: 1.0,
            usageWeight: 0.5,
            lexicalTier: .keywordInBody,
            updatedAt: "2026-07-01T00:00:00Z"
        )
        let phrase = RankedResult(
            atomUUID: "phrase",
            atomType: .note,
            title: "Old journal",
            semanticWeight: 0.1,
            structuralWeight: 0.2,
            recencyWeight: 0.1,
            usageWeight: 0.5,
            lexicalTier: .phraseInBody,
            updatedAt: "2026-01-01T00:00:00Z"
        )
        XCTAssertEqual(
            [scattered, phrase].sorted().map(\.atomUUID), ["phrase", "scattered"],
            "the exact sentence beats the same words scattered, regardless of blended score"
        )
    }

    func testLexicalMatchAwardsPhraseInBodyTier() {
        let (tier, quality) = CommandKSearchMatcher.lexicalMatch(
            normalizedQuery: CommandKSearchMatcher.normalizeQuery("compounding advantage"),
            normalizedTitle: CommandKSearchMatcher.normalize("Weekly reflections"),
            normalizedFullText: CommandKSearchMatcher.normalize(
                "Weekly reflections The compounding advantage comes from writing daily"
            )
        )
        XCTAssertEqual(tier, .phraseInBody)
        XCTAssertEqual(quality, 0.55, accuracy: 0.001)

        // Scattered tokens stay keyword-in-body.
        let (scatteredTier, _) = CommandKSearchMatcher.lexicalMatch(
            normalizedQuery: CommandKSearchMatcher.normalizeQuery("compounding advantage"),
            normalizedTitle: CommandKSearchMatcher.normalize("Weekly reflections"),
            normalizedFullText: CommandKSearchMatcher.normalize(
                "Weekly reflections The advantage of routines and compounding interest"
            )
        )
        XCTAssertEqual(scatteredTier, .keywordInBody)

        // Single-token queries never award the phrase tier.
        let (singleTier, _) = CommandKSearchMatcher.lexicalMatch(
            normalizedQuery: "compounding",
            normalizedTitle: "weekly reflections",
            normalizedFullText: "weekly reflections compounding gains"
        )
        XCTAssertEqual(singleTier, .keywordInBody)
    }

    func testQueryGrammarParsesQuotedPhrasesAndSmartQuotes() {
        let straight = HybridSearchEngine.parseQueryGrammar("\"deep work ritual\" morning")
        XCTAssertEqual(straight.quotedPhrases, ["deep work ritual"])
        XCTAssertEqual(straight.tokens, ["morning"])

        let curly = HybridSearchEngine.parseQueryGrammar("\u{201C}deep work ritual\u{201D} morning")
        XCTAssertEqual(curly.quotedPhrases, ["deep work ritual"])

        let unquoted = HybridSearchEngine.parseQueryGrammar("deep work ritual")
        XCTAssertTrue(unquoted.quotedPhrases.isEmpty)
        XCTAssertEqual(unquoted.tokens, ["deep", "work", "ritual"])

        // Unbalanced trailing quote: the open tail is treated as a phrase.
        let unbalanced = HybridSearchEngine.parseQueryGrammar("morning \"deep work")
        XCTAssertEqual(unbalanced.quotedPhrases, ["deep work"])
        XCTAssertEqual(unbalanced.tokens, ["morning"])
    }

    func testFTS5PhraseAndNearQueryPreparation() {
        XCTAssertEqual(
            HybridSearchEngine.prepareFTS5PhraseQuery("compounding advantage daily"),
            "\"compounding advantage daily\"*"
        )
        XCTAssertNil(
            HybridSearchEngine.prepareFTS5PhraseQuery("compounding"),
            "single bare tokens have no phrase to try"
        )
        XCTAssertEqual(
            HybridSearchEngine.prepareFTS5PhraseQuery("\"deep work\" morning"),
            "\"deep work\" \"morning\"*"
        )
        XCTAssertEqual(
            HybridSearchEngine.prepareFTS5NearQuery("compounding advantage daily"),
            "NEAR(\"compounding\"* \"advantage\"* \"daily\"*, 10)"
        )
        XCTAssertNil(
            HybridSearchEngine.prepareFTS5NearQuery("\"deep work\" morning"),
            "quoted queries demand exactness — no NEAR loosening"
        )
        XCTAssertNil(HybridSearchEngine.prepareFTS5NearQuery("single"))
    }

    func testTermCoverageCountsMatchedTokens() {
        let coverage = HybridSearchEngine.termCoverage(
            tokens: ["compounding", "advantage", "writing", "zxqvmissing"],
            in: "The compounding advantage of writing daily"
        )
        XCTAssertEqual(coverage, 0.75, accuracy: 0.001)
    }

    func testHybridMapperLadderTiers() {
        func searchResult(
            matchedAllTerms: Bool,
            matchedPhrase: Bool,
            termCoverage: Double
        ) -> HybridSearchEngine.SearchResult {
            HybridSearchEngine.SearchResult(
                entityType: .note,
                entityId: 1,
                entityUUID: "uuid",
                title: "Weekly notes",
                preview: "",
                bm25Score: 6,
                vectorSimilarity: 0.4,
                combinedScore: 0.4,
                matchReason: .keywordMatch,
                updatedAt: "2026-07-01T00:00:00Z",
                matchedAllTerms: matchedAllTerms,
                matchedPhrase: matchedPhrase,
                termCoverage: termCoverage
            )
        }
        let query = CommandKSearchMatcher.normalizeQuery("greenhouse ritual advantage")

        XCTAssertEqual(
            CommandKHybridResultMapper.lexicalTier(
                for: searchResult(matchedAllTerms: true, matchedPhrase: true, termCoverage: 1.0),
                normalizedQuery: query
            ),
            .phraseInBody
        )
        XCTAssertEqual(
            CommandKHybridResultMapper.lexicalTier(
                for: searchResult(matchedAllTerms: true, matchedPhrase: false, termCoverage: 1.0),
                normalizedQuery: query
            ),
            .keywordInBody
        )
        // High-coverage partial: 7-of-8-style near-misses keep keyword rank.
        XCTAssertEqual(
            CommandKHybridResultMapper.lexicalTier(
                for: searchResult(matchedAllTerms: false, matchedPhrase: false, termCoverage: 0.75),
                normalizedQuery: query
            ),
            .keywordInBody
        )
        // Low-coverage scraps rank with the semantic layer.
        XCTAssertEqual(
            CommandKHybridResultMapper.lexicalTier(
                for: searchResult(matchedAllTerms: false, matchedPhrase: false, termCoverage: 0.34),
                normalizedQuery: query
            ),
            .semanticOnly
        )
    }

    @MainActor
    func testInstantIndexQuotedQueryRequiresPhrase() {
        var index = CommandKSearchIndex()
        index.replace([
            CommandKSearchIndex.Entry(
                id: "phrase-doc",
                atomUUID: "phrase-doc",
                atomType: .note,
                title: "Journal",
                snippet: "The deep work ritual starts at dawn",
                updatedAt: "2026-07-01T00:00:00Z"
            ),
            CommandKSearchIndex.Entry(
                id: "scattered-doc",
                atomUUID: "scattered-doc",
                atomType: .note,
                title: "Notes",
                snippet: "Deep thoughts about how work and ritual interact",
                updatedAt: "2026-07-01T00:00:00Z"
            )
        ])

        let unquoted = index.search("deep work ritual", limit: 10)
        XCTAssertEqual(Set(unquoted.map(\.atomUUID)), ["phrase-doc", "scattered-doc"])
        XCTAssertEqual(
            unquoted.first?.atomUUID, "phrase-doc",
            "the contiguous phrase outranks the scattered tokens"
        )

        let quoted = index.search("\"deep work ritual\"", limit: 10)
        XCTAssertEqual(
            quoted.map(\.atomUUID), ["phrase-doc"],
            "quotes are a hard phrase requirement"
        )
    }

    func testHybridSearchPhraseBeatsScatteredTokensEndToEnd() async throws {
        let marker = "zxqvphraseladder"
        let phraseAtom = Atom.new(
            type: .note,
            title: "Buried phrase note",
            body: "Filler opening. The \(marker) sentence lives right here as one phrase. Filler closing."
        )
        let scatteredAtom = Atom.new(
            type: .note,
            title: "Scattered tokens note",
            body: "The \(marker) word appears first. Many words later, a sentence. Even later, lives and here and phrase."
        )
        let savedPhrase = try await AtomRepository.shared.create(phraseAtom)
        createdUUIDs.append(savedPhrase.uuid)
        let savedScattered = try await AtomRepository.shared.create(scatteredAtom)
        createdUUIDs.append(savedScattered.uuid)

        let results = try await HybridSearchEngine.shared.search(
            query: "\(marker) sentence lives right here",
            limit: 10
        )
        let phraseHit = results.first { $0.entityUUID == savedPhrase.uuid }
        let scatteredHit = results.first { $0.entityUUID == savedScattered.uuid }

        XCTAssertNotNil(phraseHit, "the phrase document must be retrieved")
        XCTAssertEqual(phraseHit?.matchedPhrase, true, "the ladder must mark the contiguous match as a phrase hit")
        if let scatteredHit {
            XCTAssertEqual(
                scatteredHit.matchedPhrase, false,
                "scattered tokens must not claim phrase evidence"
            )
        }
    }

    func testHybridSearchQuotedQueryReturnsOnlyPhraseMatches() async throws {
        let marker = "zxqvquotedstrict"
        let phraseAtom = Atom.new(
            type: .note,
            title: "Quoted phrase target",
            body: "Somewhere in here the \(marker) ritual begins exactly so."
        )
        let scatteredAtom = Atom.new(
            type: .note,
            title: "Quoted phrase decoy",
            body: "The ritual word is here. Much later the \(marker) word, but never together."
        )
        let savedPhrase = try await AtomRepository.shared.create(phraseAtom)
        createdUUIDs.append(savedPhrase.uuid)
        let savedScattered = try await AtomRepository.shared.create(scatteredAtom)
        createdUUIDs.append(savedScattered.uuid)

        let results = try await HybridSearchEngine.shared.search(
            query: "\"\(marker) ritual\"",
            limit: 10
        )

        XCTAssertTrue(
            results.contains { $0.entityUUID == savedPhrase.uuid },
            "the exact phrase must be found"
        )
        XCTAssertFalse(
            results.contains { $0.entityUUID == savedScattered.uuid },
            "a quoted query must never return scattered-token matches"
        )
    }

    func testHybridSearchHighCoveragePartialSurvivesMissingToken() async throws {
        let marker = "zxqvcoverageladder"
        let atom = Atom.new(
            type: .note,
            title: "Coverage note",
            body: "The \(marker) advantage comes from writing every day without fail."
        )
        let saved = try await AtomRepository.shared.create(atom)
        createdUUIDs.append(saved.uuid)

        // One token ("nonexistentterm") is misremembered — strict AND fails,
        // but 4 of 5 tokens match: the coverage ladder must keep the hit.
        let results = try await HybridSearchEngine.shared.search(
            query: "\(marker) advantage writing day nonexistentterm",
            limit: 10
        )
        let hit = results.first { $0.entityUUID == saved.uuid }

        XCTAssertNotNil(hit, "a 4-of-5-token match must survive one misremembered word")
        XCTAssertEqual(hit?.matchedAllTerms, false)
        XCTAssertEqual(hit?.termCoverage ?? 0, 0.8, accuracy: 0.01)
    }

    // MARK: - Jump-to-sentence landing (Phase 3)

    @MainActor
    func testLandingStoreIsOneShotAndKeyedByAtom() {
        let store = CommandKSearchLandingStore()
        store.stage(atomUUID: "atom-a", excerpt: "…the passage…", query: "the passage")

        XCTAssertNil(store.consume(for: "atom-b"), "another atom must not steal the landing")
        let landing = store.consume(for: "atom-a")
        XCTAssertEqual(landing?.excerpt, "…the passage…")
        XCTAssertNil(store.consume(for: "atom-a"), "landings are one-shot")

        store.stage(atomUUID: "", excerpt: nil, query: "query")
        XCTAssertNil(store.consume(for: ""), "empty identifiers never stage")
        store.stage(atomUUID: "atom-c", excerpt: nil, query: "   ")
        XCTAssertNil(store.consume(for: "atom-c"), "empty queries never stage")
    }

    @MainActor
    func testLandingLocatorFindsPhraseBlockThenExcerptOverlapThenToken() {
        let blocks = [
            RichBlock(kind: .paragraph, inlines: [.text("Opening thoughts about mornings.")]),
            RichBlock(kind: .paragraph, inlines: [.text("The compounding advantage comes from writing every day.")]),
            RichBlock(kind: .paragraph, inlines: [.text("Closing notes mention advantage once more.")])
        ]

        // 1. Whole query as a phrase inside one block.
        let phraseLanding = CommandKSearchLanding(
            atomUUID: "a", excerpt: nil, query: "compounding advantage", stagedAt: Date()
        )
        XCTAssertEqual(
            CommandKSearchLandingLocator.blockID(for: phraseLanding, in: blocks),
            blocks[1].id
        )

        // 2. No phrase hit — excerpt token overlap picks the right block.
        let overlapLanding = CommandKSearchLanding(
            atomUUID: "a",
            excerpt: "…advantage comes from writing every day…",
            query: "advantage writing zxqvmissing",
            stagedAt: Date()
        )
        XCTAssertEqual(
            CommandKSearchLandingLocator.blockID(for: overlapLanding, in: blocks),
            blocks[1].id
        )

        // 3. Nothing matches at all → nil (open normally).
        let missLanding = CommandKSearchLanding(
            atomUUID: "a", excerpt: nil, query: "zxqvnothing", stagedAt: Date()
        )
        XCTAssertNil(CommandKSearchLandingLocator.blockID(for: missLanding, in: blocks))
    }

    @MainActor
    func testLandingLocatorResolvesNestedMatchToTopLevelAnchor() {
        var toggle = RichBlock(kind: .toggle, inlines: [.text("Folded section")])
        toggle.children = [
            RichBlock(kind: .paragraph, inlines: [.text("The buried sentence hides in a toggle child.")])
        ]
        let blocks = [
            RichBlock(kind: .paragraph, inlines: [.text("Intro paragraph.")]),
            toggle
        ]

        let landing = CommandKSearchLanding(
            atomUUID: "a", excerpt: nil, query: "buried sentence hides", stagedAt: Date()
        )
        XCTAssertEqual(
            CommandKSearchLandingLocator.blockID(for: landing, in: blocks),
            toggle.id,
            "nested matches reveal their top-level row — children have no scroll anchor"
        )
    }

    // MARK: - Typo tolerance + embedding cache (Phase 4)

    func testTypoToleranceOneEditVariants() {
        XCTAssertTrue(CommandKTypoTolerance.isWithinOneEdit("retrieval"[...], "retrieval"[...]))
        XCTAssertTrue(CommandKTypoTolerance.isWithinOneEdit("retreival"[...], "retrieval"[...]), "transposition")
        XCTAssertTrue(CommandKTypoTolerance.isWithinOneEdit("retrival"[...], "retrieval"[...]), "deletion")
        XCTAssertTrue(CommandKTypoTolerance.isWithinOneEdit("retrieval"[...], "retrieva"[...]), "insertion")
        XCTAssertTrue(CommandKTypoTolerance.isWithinOneEdit("retrieval"[...], "retrieval"[...].dropLast() + "x"), "substitution")
        XCTAssertFalse(CommandKTypoTolerance.isWithinOneEdit("retreivla"[...], "retrieval"[...]), "two transpositions is two edits")
        XCTAssertFalse(CommandKTypoTolerance.isWithinOneEdit("cat"[...], "dog"[...]))
        XCTAssertFalse(CommandKTypoTolerance.isWithinOneEdit("short"[...], "muchlonger"[...]))
    }

    func testTypoTolerancePrefixMatchWhileTyping() {
        XCTAssertTrue(
            CommandKTypoTolerance.fuzzyMatches("retreiv"[...], titleToken: "retrieval"[...]),
            "a typo inside a partially-typed word must still connect via the title-token prefix"
        )
        XCTAssertFalse(
            CommandKTypoTolerance.fuzzyMatches("zzzzzz"[...], titleToken: "retrieval"[...])
        )
    }

    @MainActor
    func testInstantIndexFuzzyTitleRescueRanksBelowExactMatches() {
        var index = CommandKSearchIndex()
        index.replace([
            CommandKSearchIndex.Entry(
                id: "target",
                atomUUID: "target",
                atomType: .note,
                title: "Retrieval notes",
                snippet: "Body text",
                updatedAt: "2026-07-01T00:00:00Z"
            )
        ])

        // Typo'd query: no strict match anywhere, fuzzy title rescue fires.
        let fuzzy = index.search("retreival", limit: 10)
        XCTAssertEqual(fuzzy.map(\.atomUUID), ["target"])
        XCTAssertEqual(fuzzy.first?.lexicalTier, .titleMatch)

        // Exact query: strict path answers, quality above the fuzzy floor.
        let exact = index.search("retrieval", limit: 10)
        XCTAssertEqual(exact.first?.atomUUID, "target")
        XCTAssertGreaterThan(exact.first?.structuralWeight ?? 0, 0.5)

        // Short tokens never fuzz — "cat" must not summon "car".
        var shortIndex = CommandKSearchIndex()
        shortIndex.replace([
            CommandKSearchIndex.Entry(
                id: "car",
                atomUUID: "car",
                atomType: .note,
                title: "Car",
                snippet: nil,
                updatedAt: "2026-07-01T00:00:00Z"
            )
        ])
        XCTAssertTrue(shortIndex.search("cat", limit: 10).isEmpty)
    }

    func testQueryEmbeddingCacheStoresAndEvicts() async {
        let cache = QueryEmbeddingCache()
        await cache.store([0.1, 0.2], for: "  Compounding Advantage ")

        // Keyed by trimmed, lowercased query.
        let hit = await cache.vector(for: "compounding advantage")
        XCTAssertEqual(hit, [0.1, 0.2])

        let miss = await cache.vector(for: "something else")
        XCTAssertNil(miss)

        // Empty vectors and blank queries never cache.
        await cache.store([], for: "empty vector")
        let emptyVector = await cache.vector(for: "empty vector")
        XCTAssertNil(emptyVector)
        await cache.store([0.5], for: "   ")
        let blank = await cache.vector(for: "   ")
        XCTAssertNil(blank)
    }

    // MARK: - Research result identity (thumbnail / favicon ladder)

    /// Captured research links wear their page's identity in the rail:
    /// mirrored thumbnail first, site favicon as the fallback, identity chip
    /// only when neither exists. The rail reads both off the hydrated
    /// LibraryItem, so its construction is the seam that matters.
    func testResearchLibraryItemCarriesThumbnailAndFaviconHost() {
        var research = Atom.new(type: .research, title: "How to write hooks")
        research.metadata = """
        {"url": "https://www.lennysnewsletter.com/p/hooks", "thumbnailUrl": "https://cdn.example.com/thumb.jpg"}
        """
        let item = LibraryItem(atom: research)
        XCTAssertEqual(item.thumbnailURL, "https://cdn.example.com/thumb.jpg")
        XCTAssertEqual(item.faviconHost, "www.lennysnewsletter.com")

        // A capture with no mirrored thumbnail still gets its site favicon.
        var linkOnly = Atom.new(type: .research, title: "Pricing page teardown")
        linkOnly.metadata = #"{"url": "https://stripe.com/pricing"}"#
        let linkItem = LibraryItem(atom: linkOnly)
        XCTAssertNil(linkItem.thumbnailURL)
        XCTAssertEqual(linkItem.faviconHost, "stripe.com")

        // Non-research atoms never wear a favicon.
        let note = Atom.new(type: .note, title: "Plain note")
        XCTAssertNil(LibraryItem(atom: note).faviconHost)
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
