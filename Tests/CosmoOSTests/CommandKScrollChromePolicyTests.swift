import XCTest

final class CommandKScrollChromePolicyTests: XCTestCase {
    func testCommandKUsesContentFocusSizedScrollbarsForRailAndDetailPane() throws {
        let root = repositoryRoot
        let style = try String(
            contentsOf: root.appendingPathComponent("UI/CommandK/CortexScrollChrome.swift"),
            encoding: .utf8
        )
        let rail = try String(
            contentsOf: root.appendingPathComponent("UI/CommandK/CortexResultRail.swift"),
            encoding: .utf8
        )
        let detail = try String(
            contentsOf: root.appendingPathComponent("UI/CommandK/CortexDetailPane.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(style.contains("private static let trackWidth: CGFloat = 2"))
        XCTAssertTrue(style.contains("private static let thumbWidth: CGFloat = 2.5"))
        XCTAssertTrue(style.contains("scrollView.hasVerticalScroller = false"))
        // Store-backed variant: scroll ticks invalidate only the scrollbar
        // host, never the pane's whole body (July 2026 scroll-jank fix).
        XCTAssertTrue(rail.contains(".cortexThinScrollbar(store: railScrollMetrics)"))
        XCTAssertTrue(detail.contains(".cortexThinScrollbar(store: detailScrollMetrics)"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
