import XCTest
import Combine
@testable import CosmoOS

@MainActor
final class PaneManagerBrowserPaneTests: XCTestCase {
    func testCosmoWindowPaneOpensOnceAndReactivatesUnifiedChatPane() {
        let manager = PaneManager()

        manager.openOrActivateCosmoWindow()

        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(manager.mainSplitRatio, 0.5)
        XCTAssertEqual(manager.panes.count, 1)
        XCTAssertEqual(manager.panes.first?.id, "cosmoWindow")
        XCTAssertEqual(manager.activePaneId, "cosmoWindow")

        manager.openOrActivateCosmoWindow()

        XCTAssertEqual(manager.panes.count, 1)
        XCTAssertEqual(manager.activePaneId, "cosmoWindow")
    }

    func testBrowserPaneOpensOncePerURLAndActivatesSplitPane() {
        let manager = PaneManager()
        let url = URL(string: "https://www.instagram.com/reel/example/")!

        XCTAssertTrue(manager.canOpenBrowser(url: url))

        manager.openPane(.webBrowser(url: url, title: "Instagram"))

        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(manager.mainSplitRatio, 0.5)
        XCTAssertEqual(manager.panes.count, 1)
        XCTAssertEqual(manager.activePaneId, "web_\(url.absoluteString)")
        XCTAssertFalse(manager.canOpenBrowser(url: url))

        manager.openPane(.webBrowser(url: url, title: "Instagram"))

        XCTAssertEqual(manager.panes.count, 1)
    }

    func testSwipeGalleryPaneOpensOnceAndActivatesSplitPane() {
        let manager = PaneManager()

        XCTAssertTrue(manager.canOpenSwipeGallery())

        manager.openPane(.swipeGallery)

        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(manager.mainSplitRatio, 0.5)
        XCTAssertEqual(manager.panes.count, 1)
        XCTAssertEqual(manager.panes.first?.id, "swipeGallery")
        XCTAssertEqual(manager.activePaneId, "swipeGallery")
        XCTAssertFalse(manager.canOpenSwipeGallery())

        manager.openPane(.swipeGallery)

        XCTAssertEqual(manager.panes.count, 1)
    }

    func testSplitPaneContainerDoesNotImplicitlyAnimateEveryResizeFrame() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/SplitPaneContainer.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains(".animation(ProMotionSprings.snappy, value: paneManager.mainSplitRatio)"))
    }

    func testCollapsedPaneContentMovesAwayFromSpineHitZone() {
        XCTAssertEqual(
            PaneSlotPresentationPolicy.contentOffset(isExpanded: true, expandedWidth: 520),
            0
        )
        XCTAssertLessThan(
            PaneSlotPresentationPolicy.contentOffset(isExpanded: false, expandedWidth: 520),
            -520
        )
    }

    func testCollapsedPaneHoverDwellMatchesFastSpineReveal() {
        XCTAssertEqual(PaneSlotPresentationPolicy.hoverDwellMilliseconds, 150)
    }

    func testLeftCollapsedSpineTouchesFollowingExpandedPane() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/SplitPaneContainer.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("static func interSlotSpacing(leftIsExpanded: Bool, rightIsExpanded: Bool) -> CGFloat"),
            "Pane slot spacing must be directional so a left-side collapsed spine can touch the following expanded pane."
        )
        XCTAssertTrue(
            source.contains("if !leftIsExpanded && rightIsExpanded { return 0 }"),
            "Only the collapsed-left / expanded-right edge should close its visual gap."
        )
        XCTAssertTrue(
            source.contains("HStack(spacing: 0)"),
            "The deck must render explicit per-edge spacers instead of one fixed HStack spacing."
        )
        XCTAssertTrue(
            source.contains("layout.spacingAfter[pane.id]"),
            "The rendered deck must use the layout's directional spacing for each pane edge."
        )
    }

    func testCollapsedPaneSlotAnchorsVisibleFrameToSpineWidth() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/SplitPaneContainer.swift"),
            encoding: .utf8
        )
        let callStart = try XCTUnwrap(source.range(of: "PaneSlotView(")?.lowerBound)
        let callEnd = try XCTUnwrap(source[callStart...].range(of: "onFocus:")?.lowerBound)
        let slotCall = String(source[callStart..<callEnd])

        XCTAssertTrue(
            slotCall.contains("slotWidth: slotWidth"),
            "PaneSlotView must receive the deck slot width so collapsed slots paint from the 44pt spine bounds."
        )

        let viewStart = try XCTUnwrap(source.range(of: "private struct PaneSlotView")?.lowerBound)
        let badgeStart = try XCTUnwrap(source.range(of: "private var pinnedBadge")?.lowerBound)
        let slotView = String(source[viewStart..<badgeStart])

        XCTAssertTrue(slotView.contains("let slotWidth: CGFloat"))
        XCTAssertTrue(
            slotView.contains(".frame(width: slotWidth, alignment: .leading)"),
            "The slot root must be fixed to the visible slot width with leading alignment before clipping."
        )
        XCTAssertLessThan(
            try XCTUnwrap(slotView.range(of: ".frame(width: slotWidth, alignment: .leading)")?.lowerBound),
            try XCTUnwrap(slotView.range(of: ".clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))")?.lowerBound)
        )
    }

    func testPaneContentChromeFillsAssignedSlotBeforePaintingBackground() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/PaneContentView.swift"),
            encoding: .utf8
        )
        let bodyStart = try XCTUnwrap(source.range(of: "var body: some View {")?.lowerBound)
        let taskStart = try XCTUnwrap(source.range(of: ".task(id: content.entitySelection)")?.lowerBound)
        let bodyChrome = String(source[bodyStart..<taskStart])

        XCTAssertTrue(
            bodyChrome.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"),
            "Pane chrome must expand to the deck slot before drawing its background and border."
        )
        XCTAssertLessThan(
            try XCTUnwrap(bodyChrome.range(of: ".frame(maxWidth: .infinity, maxHeight: .infinity)")?.lowerBound),
            try XCTUnwrap(bodyChrome.range(of: ".background(backgroundFill)")?.lowerBound)
        )
    }

    func testBrowserStateDoesNotRepublishIdenticalSnapshots() {
        let url = URL(string: "https://www.instagram.com/reel/example/")!
        let state = CosmoWebBrowserState(initialURL: url, title: "Instagram")
        var publishCount = 0

        let cancellable = state.objectWillChange.sink { _ in
            publishCount += 1
        }

        state.applySnapshot(
            url: url,
            title: "Instagram",
            isLoading: false,
            estimatedProgress: 0,
            canGoBack: false,
            canGoForward: false
        )

        XCTAssertEqual(publishCount, 0)
        withExtendedLifetime(cancellable) {}
    }

    func testBrowserWebViewObservesURLChangesOutsideNavigationDelegateCallbacks() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/CosmoWebBrowserPane.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("installWebViewObservers(for: webView)"),
            "The browser bridge must observe WKWebView state directly so client-side route changes update the address field."
        )
        XCTAssertTrue(
            source.contains("webView.observe(\\.url"),
            "WKWebView.url is KVO-compliant and should drive address updates for same-document SPA navigation."
        )
    }

    func testBrowserChromeUsesFavoriteLanguageAndAdaptiveOverflow() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/CosmoWebBrowserPane.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private var favoriteLimitForBar: Int"))
        XCTAssertTrue(source.contains("private var visibleFavorites: [CosmoBrowserPinnedSite]"))
        XCTAssertTrue(source.contains("private var overflowFavorites: [CosmoBrowserPinnedSite]"))
        XCTAssertTrue(source.contains("Label(\"Open Favorite\", systemImage: \"arrow.up.forward.app\")"))
        XCTAssertTrue(source.contains("Label(\"Rename Favorite\", systemImage: \"pencil\")"))
        XCTAssertTrue(source.contains("Label(\"Remove Favorite\", systemImage: \"trash\")"))
        XCTAssertTrue(source.contains("Image(systemName: \"ellipsis.circle\")"))
    }

    func testBrowserStartPageQuickAccessIsWiredToHomeURL() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/CosmoWebBrowserPane.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@Published var showsStartPage: Bool"))
        XCTAssertTrue(source.contains("self.showsStartPage = initialURL == CosmoBrowserURLResolver.defaultHomeURL"))
        XCTAssertTrue(source.contains("CosmoBrowserStartPage("))
        XCTAssertTrue(source.contains("favorites: browserState.pins"))
        XCTAssertTrue(source.contains("recentHistory: browserState.recentHistory"))
        XCTAssertTrue(source.contains("showsStartPage = false"))
    }

    func testBrowserURLResolverAcceptsBareDomainsAndSearchQueries() {
        XCTAssertEqual(
            CosmoBrowserURLResolver.resolve("example.com")?.absoluteString,
            "https://example.com"
        )
        XCTAssertEqual(
            CosmoBrowserURLResolver.resolve("creator economy research")?.absoluteString,
            "https://www.google.com/search?q=creator%20economy%20research"
        )
    }

    func testBrowserSessionRecordsVisitsAndPinsNormalizedSites() {
        let url = URL(string: "https://www.example.com/articles?id=1")!
        var session = CosmoBrowserSession.starting(at: url, title: "Example")

        session.recordVisit(url: url, title: "Example Article", at: Date(timeIntervalSince1970: 10))
        let pin = session.pinCurrentSite(at: Date(timeIntervalSince1970: 12))

        XCTAssertEqual(session.tabs.count, 1)
        XCTAssertEqual(session.tabs[0].title, "Example Article")
        XCTAssertEqual(session.tabs[0].history.count, 1)
        XCTAssertEqual(pin?.host, "example.com")
        XCTAssertEqual(pin.map { session.pinnedSites.contains($0) }, true)
    }

    func testBrowserPinnedSiteCanBeRenamedAndPersistsDisplayName() async throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CosmoBrowserStore(fileURL: stateURL)
        var pin = CosmoBrowserPinnedSite(
            url: URL(string: "https://www.instagram.com/josh")!,
            title: "Instagram",
            pinnedAt: Date(timeIntervalSince1970: 16)
        )

        XCTAssertEqual(pin.displayName, "Instagram")

        pin.rename(to: "Instagram Josh")
        try await store.savePins([pin], for: CosmoBrowserProfile.standard.id)
        try await store.renamePin(pin.id, to: "Josh Research", for: CosmoBrowserProfile.standard.id)

        let savedPins = await store.pins(for: CosmoBrowserProfile.standard.id)
        XCTAssertEqual(savedPins.first?.displayName, "Josh Research")
        XCTAssertTrue(savedPins.first?.searchableText.localizedCaseInsensitiveContains("Josh Research") == true)

        try? FileManager.default.removeItem(at: stateURL)
    }

    func testBrowserStoreKeepsMultipleFavoritesOnSameHost() async throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CosmoBrowserStore(fileURL: stateURL)
        let first = CosmoBrowserPinnedSite(
            url: URL(string: "https://www.instagram.com/josh/")!,
            title: "Josh",
            displayName: "Josh"
        )
        let second = CosmoBrowserPinnedSite(
            url: URL(string: "https://www.instagram.com/euan/")!,
            title: "Euan",
            displayName: "Euan"
        )

        _ = try await store.upsertPin(first, for: CosmoBrowserProfile.standard.id)
        let pins = try await store.upsertPin(second, for: CosmoBrowserProfile.standard.id)

        XCTAssertEqual(pins.map(\.url), [second.url, first.url])
        XCTAssertEqual(Set(pins.map(\.displayName)), ["Josh", "Euan"])

        try? FileManager.default.removeItem(at: stateURL)
    }

    func testBrowserStateMarksOnlyExactCurrentPageAsFavorited() {
        let first = URL(string: "https://www.instagram.com/josh/")!
        let second = URL(string: "https://www.instagram.com/euan/")!
        let state = CosmoWebBrowserState(initialURL: first, title: "Josh")

        state.pins = [
            CosmoBrowserPinnedSite(url: first, title: "Josh", displayName: "Josh")
        ]
        XCTAssertTrue(state.isCurrentSitePinned)

        state.applySnapshot(
            url: second,
            title: "Euan",
            isLoading: false,
            estimatedProgress: 1,
            canGoBack: true,
            canGoForward: false
        )
        XCTAssertFalse(state.isCurrentSitePinned)
    }

    func testBrowserStateRemovingOneSameHostFavoriteKeepsTheOther() async throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CosmoBrowserStore(fileURL: stateURL)
        let first = CosmoBrowserPinnedSite(
            url: URL(string: "https://www.instagram.com/josh/")!,
            title: "Josh",
            displayName: "Josh"
        )
        let second = CosmoBrowserPinnedSite(
            url: URL(string: "https://www.instagram.com/euan/")!,
            title: "Euan",
            displayName: "Euan"
        )
        try await store.savePins([first, second], for: CosmoBrowserProfile.standard.id)
        let state = CosmoWebBrowserState(initialURL: first.url, title: "Josh", store: store)

        await state.loadPersistedPins()
        state.unpin(first)
        let pins = try await waitForPins(in: store, profileID: CosmoBrowserProfile.standard.id, count: 1)

        XCTAssertEqual(pins.map(\.url), [second.url])
        XCTAssertEqual(state.pins.map(\.url), [second.url])

        try? FileManager.default.removeItem(at: stateURL)
    }

    func testPinningFromFreshBrowserStateMergesWithExistingProfilePins() async throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CosmoBrowserStore(fileURL: stateURL)
        let existingPin = CosmoBrowserPinnedSite(
            url: URL(string: "https://www.first.example")!,
            title: "First",
            pinnedAt: Date(timeIntervalSince1970: 24)
        )
        try await store.savePins([existingPin], for: CosmoBrowserProfile.standard.id)

        let state = CosmoWebBrowserState(
            initialURL: URL(string: "https://www.second.example")!,
            title: "Second",
            store: store
        )

        state.pinCurrentSite()
        let pins = try await waitForPins(in: store, profileID: CosmoBrowserProfile.standard.id, count: 2)

        XCTAssertEqual(Set(pins.map(\.host)), ["first.example", "second.example"])

        try? FileManager.default.removeItem(at: stateURL)
    }

    func testPinButtonDoesNotRemoveExistingPinForCurrentSite() async throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CosmoBrowserStore(fileURL: stateURL)
        let state = CosmoWebBrowserState(
            initialURL: URL(string: "https://www.example.com")!,
            title: "Example",
            store: store
        )

        state.pinCurrentSite()
        _ = try await waitForPins(in: store, profileID: CosmoBrowserProfile.standard.id, count: 1)

        state.pinCurrentSite()
        let pins = try await waitForPins(in: store, profileID: CosmoBrowserProfile.standard.id, count: 1)

        XCTAssertEqual(pins.map(\.host), ["example.com"])
        XCTAssertEqual(state.pins.map(\.host), ["example.com"])

        try? FileManager.default.removeItem(at: stateURL)
    }

    func testBrowserProfilesDeclareWebsiteDataAndAuthenticationPolicy() {
        XCTAssertEqual(CosmoBrowserProfile.standard.websiteDataMode, .defaultPersistent)
        XCTAssertEqual(CosmoBrowserProfile.privateBrowsing.websiteDataMode, .privateMemory)
        XCTAssertEqual(CosmoBrowserProfile.research.websiteDataMode, .isolatedPersistent(CosmoBrowserProfile.research.websiteDataIdentifier))
    }

    func testResearchCaptureIncludesSelectionAndSourceURL() {
        let url = URL(string: "https://example.com/report")!
        let capture = CosmoBrowserResearchCapture(
            kind: .quote,
            sourceURL: url,
            pageTitle: "Market Report",
            selectedText: "Distribution beats virality.",
            createdAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(capture.title, "Market Report")
        XCTAssertEqual(capture.body, "Distribution beats virality.")
        XCTAssertEqual(capture.sourceURL.absoluteString, "https://example.com/report")
    }

    func testAuthenticationPolicyFlagsGoogleOAuthForSystemSession() {
        let url = URL(string: "https://accounts.google.com/o/oauth2/v2/auth?client_id=abc")!

        XCTAssertEqual(
            CosmoBrowserAuthenticationPolicy.recommendedRoute(for: url),
            .externalSystemSession(reason: "Google OAuth blocks many embedded browser sign-in flows.")
        )
    }

    func testBrowserStateSwitchesProfilesAndLoadsProfilePins() async throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CosmoBrowserStore(fileURL: stateURL)
        let pin = CosmoBrowserPinnedSite(
            url: URL(string: "https://research.example.com")!,
            title: "Research Example",
            pinnedAt: Date(timeIntervalSince1970: 30)
        )
        try await store.savePins([pin], for: CosmoBrowserProfile.research.id)

        let state = CosmoWebBrowserState(
            initialURL: URL(string: "https://example.com")!,
            title: "Example",
            store: store
        )

        await state.switchProfile(.research)

        XCTAssertEqual(state.profile, .research)
        XCTAssertEqual(state.pins, [pin])
        XCTAssertEqual(state.profile.websiteDataMode, .isolatedPersistent(CosmoBrowserProfile.research.websiteDataIdentifier))

        try? FileManager.default.removeItem(at: stateURL)
    }

    func testBrowserStorePersistsRecentHistoryByProfile() async throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = CosmoBrowserStore(fileURL: stateURL)
        let first = CosmoBrowserHistoryItem(
            url: URL(string: "https://example.com/one")!,
            title: "One",
            visitedAt: Date(timeIntervalSince1970: 40)
        )
        let second = CosmoBrowserHistoryItem(
            url: URL(string: "https://example.com/two")!,
            title: "Two",
            visitedAt: Date(timeIntervalSince1970: 41)
        )

        try await store.recordVisit(first, for: CosmoBrowserProfile.standard.id)
        try await store.recordVisit(second, for: CosmoBrowserProfile.standard.id)

        let history = await store.history(for: CosmoBrowserProfile.standard.id)
        XCTAssertEqual(history.map(\.title), ["Two", "One"])

        try? FileManager.default.removeItem(at: stateURL)
    }

    private func waitForPins(
        in store: CosmoBrowserStore,
        profileID: String,
        count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [CosmoBrowserPinnedSite] {
        var latest: [CosmoBrowserPinnedSite] = []
        for _ in 0..<20 {
            latest = await store.pins(for: profileID)
            if latest.count == count {
                return latest
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Expected \(count) pins, found \(latest.count)", file: file, line: line)
        return latest
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
