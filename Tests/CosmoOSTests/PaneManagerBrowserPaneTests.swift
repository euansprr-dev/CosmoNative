import XCTest
import Combine
@testable import CosmoOS

@MainActor
final class PaneManagerBrowserPaneTests: XCTestCase {
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
}
