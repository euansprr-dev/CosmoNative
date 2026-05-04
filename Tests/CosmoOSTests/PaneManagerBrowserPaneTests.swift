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
}
